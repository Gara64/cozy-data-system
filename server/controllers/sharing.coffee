Sharing = require '../lib/sharing'
async = require 'async'
crypto = require("crypto")

addAccess = require('../lib/token').addAccess
db = require('../helpers/db_connect_helper').db_connect()

# Randomly generates a password.
# Note that with a long enough password (eg 256), it could be used as an AES
# key to encrypt data
generatePassword = (length) ->
    return crypto.randomBytes(length)

# For each rule, check the docID doesn't already exist in database
checkRules = (rules, callback) ->
    console.log 'rules : ' + JSON.stringify rules
    async.each rules, (rule, cb) ->
        console.log 'rule : ' + JSON.stringify rule

        # Get the header instead of the whole doc
        db.head rule.id, (err, opt1, opt2) ->
            console.log JSON.stringify opt1
            console.log JSON.stringify opt2
            cb err
    , (err) ->
        callback err



# Creation of the Sharing document
#
# The structure of a Sharing document is as following. 
# Note that the [generated] fields to not need to be indicated
# share {
#   id        -> [generated] the id of the sharing document. 
#                This id will sometimes be refered as the shareID
#   desc      -> a human-readable description of what is shared
#   rules[]   -> a set of rules describing which documents will be shared,
#                providing their id and their docType
#   targets[] -> an array containing the users to whom the documents will be
#                shared. See below for a description of this structure
#   sync      -> boolean that indicates if the sharing is synchronous or not
#                The sync is one-way, from sharer to recipient
#   docType   -> [generated] Automatically set at 'sharing'
# }
#
# The target structure:
# target {
#   url           -> the url of the cozy's recipient
#   pwd           -> [generated] the password linked to the sharing process,
#                    sent by the recipient
#   repID         -> [generated] the id generated by CouchDB for the replication
# }
module.exports.create = (req, res, next) ->
    share = req.body

    # Check the targets are not empty
    unless share.targets?.length > 0
        err = new Error "Bad request"
        err.status = 400
        return next err
    
    # The docType is fixed
    share.docType = "sharing"

    # save the share document in the database
    db.save share, (err, res) ->
        if err?
            next err
        else
            share.shareID = res._id
            req.share = share
            next()

# Delete an existing sharing, identified by its id
module.exports.delete = (req, res, next) ->
    # check if the information is available
    if not req.params.id?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        shareID = req.params.id

        # Get all the targets in the sharing document
        db.get shareID (err, doc) ->
            if err?
                next err
            else
                share = 
                    shareID: shareID
                    targets: doc.targets
                    desc: "The sharing #{share.id} has been deleted"

                # remove the sharing document in the database
                db.remove shareID, (err, res) ->
                    return next err if err?
                    req.share = share
                    next()


# Send a notification for each target defined in the share object
# The minimal structure is the following :
# share {
#   shareID    -> the id of the sharing process
#   targets[]  -> the targets to notify. Each target must have an url
#   desc       -> the description of the notification
# }
# Note that additional fields can be specified, depending on the request's type
module.exports.notifyTargets = (req, res, next) ->
    if not req.share?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        share = req.share
        # Get the cozy's url
        Sharing.getDomain (err, domain) ->
            if err?
                next new Error 'No instance domain set'
            else
                share.hostUrl = domain

                # XXX Debug
                console.log 'request : ' + JSON.stringify share

                # Notify each target
                async.each share.targets, (target, callback) ->
                    # Send the target url for the answer
                    share.url = target.url
                    Sharing.notifyTarget target.url, share, (err, result, body) ->
                        if err?
                            callback err
                        else if not result?.statusCode?
                            err = new Error "Bad request"
                            err.status = 400
                            callback err
                        else if body.error?
                            err = body
                            err.status = result.statusCode
                            callback err
                        else
                            res.status(result.statusCode).send body
                            callback()
                , (err) ->
                    return next err if err?


# Create access if the sharing answer is yes, remove the Sharing doc otherwise.
#
# The access will grant permissions to the sharer, only on the documents
# specified in the sharing request.
# The shareID is then used as a login and a password is generated.
#
# Params must contains :
#   * id        -> the id of the Sharing document, created when the sharing
#                  request was received
#   * shareID   -> the id of the Sharing document created by the sharer.
#                  This will be used as the sharer's login
#   * accepted  -> boolean specifying if the share was accepted or not
#   * url       -> the url of the cozy
#   * rules     -> the set of rules specifying which documents are shared,
#                  with their docTypes.
#   * hostUrl   -> the url of the sharer's cozy
module.exports.handleRecipientAnswer = (req, res, next) ->

    params = req.body

    # Check params
    unless params.id? and params.shareID? and params.accepted? \
    and params.url? and params.rules? and params.hostUrl?
        err = new Error "Bad request"
        err.status = 400
        return next err
    
    # Create an access if the sharing is accepted
    if params.accepted is yes
        # Check all the rules to be sure none docID already exists in the db.
        # This is done to prevent unexpected access on existing documents
        checkRules params.rules, (err) ->
            if err?
                err = "A requested document already exists in the database"
                err.status = 400
                next err
            else
                access =
                    login: params.shareID
                    password: generatePassword 256
                    id: params.id
                    rules: params.rules

                addAccess access, (err, doc) ->
                    return next err if err?

                    params.pwd = access.password
                    req.params = params
                    next()

        # TODO : enforce the docType protection with the couchDB's document
        # update validation

    # Delete the Sharing doc if the sharing is refused
    else
        db.remove req.params.id, (err, res) ->
            return next err if err?
            req.params = params
            next()


# Send the answer to the emitter of the sharing request
#
# Params must contain:
#   * shareID  -> the id of the Sharing document generated by the sharer
#   * url      -> the url of the receiver's cozy
#   * accepted -> boolean telling if request was accepted/denied
#   * pwd      -> the password generated by the receiver if the request was
#                 accepted
#   * hostUrl  -> the url of the sharer's cozy
module.exports.sendAnswer = (req, res, next) ->

    # XXX DEBUG
    console.log 'params ' + JSON.stringify req.params

    params = req.params
    if not params?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        answer =
            shareID: params.shareID
            url: params.url
            accepted: params.accepted
            pwd: params.pwd

        Sharing.answerHost params.hostUrl, answer, (err, result, body) ->
            if err?
                next err
            else if not result?.statusCode?
                err = new Error "Bad request"
                err.status = 400
                next err
            else
                res.status result.statusCode


# Process the answer given by the target regarding the sharing request
# sent to him.
#
# The structure of the answer received is as following:
# answer {
#   shareID    -> the id of the sharing request
#   url        -> the url of the target
#   accepted   -> whether or not the target has accepted the request
#   pwd        -> the password generated by the target, if accepted
# }
#
module.exports.validateTarget = (req, res, next) ->
    console.log 'answer : ' + JSON.stringify req.body

    answer = req.body
    unless answer.shareID? and answer.url? and answer.accepted?
        err = new Error "Bad request"
        err.status = 400
        return next err
    
    # Get the Sharing document thanks to its id
    db.get answer.shareID, (err, doc) ->
        return next err if err?

        # Get the answering target
        target = t for t in doc.targets when t.url = answer.url
        if not target?
            err = new Error answer.url + " not found for this sharing"
            err.status = 404
            next err
        else
            # The target has accepted the sharing : save the password 
            if answer.accepted
                target.pwd = answer.pwd
            # The target has refused the sharing : remove the target
            else
                i = doc.targets.indexOf target
                doc.targets.splice i, 1

            # Update the Sharing doc
            db.merge doc._id, doc, (err, res) ->
                return next err if err?

                # Retrieve all the docIDs
                docIDs = (rule.id for rule in doc.rules)

                # Params structure for the replication
                replicate =
                    target: target
                    id: doc._id
                    docIDs: docIDs
                    sync: doc.sync

                req.params = replicate
                next()


# Replicate documents to the target url

# The structure of the replication :
# params {
#   id         -> the Sharing id, used as a login
#   target     -> contains the url and the password of the target
#   docIDs     -> the docIDs to replicate
#   sync       -> if the sharing is synchronous or not
# }
#
module.exports.replicate = (req, res, next) ->
    replicate = req.params

    # Replicate only if the target has accepted, i.e. gave a password
    if replicate.target.pwd?
        Sharing.replicateDocs replicate, (err, repID) ->
            if err?
                next err
            else if not repID?
                err = new Error "Replication failed"
                err.status = 500
                next err
            else
                # Update the target with the repID
                db.get replicate.id, (err, doc) ->
                    return next err if err?

                    # Find the target in the db
                    targetUrl = req.replicate.target.url
                    target = t for t in doc.targets when t.url = targetUrl
                     # Get index of the target and update it
                    i = doc.targets.indexOf target
                    doc.targets[i].repID = repID

                    db.merge replicate.id, (err, res) ->
                        return next err if err?

                        res.status(200).send success: true
    else
        res.status(200).send success: true

# Stop current replications for each specified target
# share {
#   targets[]  -> Each target must have an url and a repID
# }
module.exports.stopReplications = (req, res, next) ->
    share = req.share

    if not share?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        # Cancel the replication for all the targets
        async.each share.targets, (target, cb) ->
            if target.repID?
                Sharing.cancelReplication target.repID, (err) ->
                    cb err
            else
                cb()
        , (err) ->
            next err

