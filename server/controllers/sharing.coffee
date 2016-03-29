Sharing = require '../lib/sharing'
async = require "async"
crypto = require "crypto"
util = require 'util'
log = require('printit')
    prefix: 'sharing'

libToken = require('../lib/token')

db = require('../helpers/db_connect_helper').db_connect()

TOKEN_LENGTH = 32

# Randomly generates a token.
generateToken = (length) ->
    return crypto.randomBytes(length).toString('hex')


# Creation of the Sharing document
#
# The structure of a Sharing document is as following.
# Note that the [generated] fields to not need to be indicated
# share {
#   id         -> [generated] the id of the sharing document.
#                 This id will sometimes be refered as the shareID
#   desc       -> [optionnal] a human-readable description of what is shared
#   rules[]    -> a set of rules describing which documents will be shared,
#                 providing their id and their docType
#   targets[]  -> an array containing the users to whom the documents will be
#                 shared. See below for a description of this structure
#   continuous -> [optionnal] boolean that indicates if the sharing is synchronous
#                 set at false by default
#                 The sync is one-way, from sharer to recipient
#   docType    -> [generated] Automatically set at 'sharing'
# }
#
# The target structure:
# target {
#   url           -> the url of the cozy's recipient
#   preToken      -> [generated] a token used to authenticate the target's answer
#   token         -> [generated] the token linked to the sharing process,
#                    sent by the recipient
#   repID         -> [generated] the id generated by CouchDB for the replication
# }
module.exports.create = (req, res, next) ->
    share = req.body

    # Check that the body isn't empty: it exists and has at least 1 element
    unless share? and Object.keys(share).length > 0
        err = new Error "Bad request: no body"
        err.status = 400
        return next err

    # Check the targets are not empty...
    unless share.targets?.length > 0
        err = new Error "No target specified"
        err.status = 400
        return next err
    # ...and with a url
    for target in share.targets
        if not target.url? or target.url is ''
            err = new Error "No url specified"
            err.status = 400
            return next err

    # Check that rules are specified...
    unless share.rules?.length > 0
        err = new Error "No rules specified"
        err.status = 400
        return next err
    # ...and well formed
    for rule in share.rules
        if not rule.docType? or rule.docType is "" or not rule.id? or
                rule.id is ""
            err = new Error "Incorrect rule detected"
            err.status = 400
            return next err

    # The docType is fixed
    share.docType = "sharing"

    # Generate a preToken for each target
    for target in share.targets
        target.preToken = generateToken TOKEN_LENGTH

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
    if not req.params?.id?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        shareID = req.params.id

        # Get all the targets in the sharing document
        db.get shareID, (err, doc) ->
            if err?
                next err
            else
                share =
                    shareID: shareID
                    targets: doc.targets

                # remove the sharing document in the database
                db.remove shareID, (err, res) ->
                    return next err if err?
                    req.share = share
                    next()


# Send a sharing request for each target defined in the share object
# It will be viewed as a notification on the targets side
# Params must contains :
#   shareID    -> the id of the sharing process
#   rules[]    -> the set of rules specifying which documents are shared,
#                 with their docTypes.
#   targets[]  -> the targets to notify. Each target must have an url
#                 and a preToken
module.exports.sendSharingRequests = (req, res, next) ->

    share = req.share

    # Notify each target
    async.each share.targets, (target, callback) ->
        request =
            url: target.url
            preToken: target.preToken
            shareID: share.shareID
            rules: share.rules
            desc: share.desc

        log.info "Send sharing request to : #{request.url}"

        Sharing.notifyTarget "services/sharing/request", request,
        (err, result) ->
            callback err

    , (err) ->
        if err?
            next err
        else
            res.status(200).send success: true


# Send a sharing request for each target defined in the share object
# It will be viewed as a notification on the targets side
# Params must contains :# share {
#   shareID    -> the id of the sharing process
#   targets[]  -> the targets to notify. Each target must have an url
#                 and a token
module.exports.sendDeleteNotifications = (req, res, next) ->
    share = req.share

    # Notify each target
    async.each share.targets, (target, callback) ->
        notif =
            url: target.url
            token: if target.token? then target.token else target.preToken
            shareID: share.shareID
            desc: "The sharing #{share.shareID} has been deleted"

        log.info "Send sharing cancel notification to : #{notif.url}"

        Sharing.notifyTarget "services/sharing/cancel", notif,
        (err, result) ->
            callback err
    , (err) ->
        if err?
            next err
        else
            res.status(200).send success: true


# Create access if the sharing answer is yes, remove the Sharing doc otherwise.
#
# The access will grant permissions to the sharer, only on the documents
# specified in the sharing request.
# The shareID is then used as a login and a token is generated.
#
# Params must contains :
#   id        -> the id of the Sharing document, created when the sharing
#                request was received
#   shareID   -> the id of the Sharing document created by the sharer.
#                This will be used as the sharer's login
#   accepted  -> boolean specifying if the share was accepted or not
#   preToken  -> the token sent by the sharer to authenticate the receiver
#   url       -> the url of the cozy
#   hostUrl   -> the url of the sharer's cozy
#   rules     -> the set of rules specifying which documents are shared,
#                with their docTypes.
module.exports.handleRecipientAnswer = (req, res, next) ->

    if not req.body? or Object.keys(req.body).length == 0
        err = new Error "Bad request: body is missing"
        err.status = 400
        return next err

    share = req.body

    # Check share structure: each element must not be null/undefined/empty
    if not share.id?    or share.id is ''          or
    not share.shareID?  or share.shareID is ''     or
    not share.preToken? or share.preToken is ''    or
    not share.accepted? or share.accepted is ''    or
    not share.url?      or share.url is ''         or
    not share.hostUrl?  or share.hostUrl is ''     or
    not share.rules?    or not share.rules.length? or share.rules.length == 0
        err = new Error "Bad request: body is incomplete"
        err.status = 400
        return next err
    # Same for the rules structure: each rule must have an id and a docType
    for rule in share.rules
        if not rule.id?   or rule.id is ''      or
        not rule.docType? or rule.docType is ''
            err = new Error "Bad request: incorrect rule detected"
            err.status = 400
            return next err

    # Create an access if the sharing is accepted
    if share.accepted is yes
        access =
            login: share.shareID
            password: generateToken TOKEN_LENGTH
            id: share.id
            rules: share.rules

        libToken.addAccess access, (err, doc) ->
            return next err if err?

            share.token = access.password
            req.share = share
            return next()

        # TODO : enforce the docType protection with the couchDB's document
        # update validation

    # Delete the Sharing doc if the sharing is refused
    else
        db.remove share.id, (err, res) ->
            return next err if err?
            req.share = share
            next()


# Send the answer to the emitter of the sharing request
#
# Params must contain:
#   shareID   -> the id of the Sharing document generated by the sharer
#   url       -> the url of the cozy
#   accepted  -> boolean specifying if the share was accepted or not
#   preToken  -> the token sent by the sharer to authenticate the receiver
#   token     -> the token generated by the receiver if the request was
#                accepted
#   hostUrl   -> the url of the sharer's cozy
module.exports.sendAnswer = (req, res, next) ->
    share = req.share

    if not share?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        # Note that we switch the url and hostUrl
        answer =
            shareID: share.shareID
            hostUrl: share.url
            url: share.hostUrl
            accepted: share.accepted
            preToken: share.preToken
            token: share.token

        log.info "Send sharing answer to : #{answer.url}"

        Sharing.notifyTarget "services/sharing/answer", answer,
        (err, result, body) ->
            if err?
                next err
            else
                res.status(200).send success: true


# Process the answer given by a target regarding the sharing request
# previously sent.
#
# Params must contain:
#   shareID    -> the id of the sharing request
#   hostUrl    -> the url of the target
#   accepted   -> boolean specifying if the share was accepted or not
#   preToken   -> the token sent by the sharer to authenticate the receiver
#   token      -> the token generated by the target, if accepted
module.exports.validateTarget = (req, res, next) ->
    # safety check...
    if not req.body?
        err = new Error "Bad request"
        err.status = 400
        return next err

    answer = req.body

    # Check the structure of the answer
    unless answer.shareID? and answer.shareID isnt "" and answer.hostUrl? and
    answer.hostUrl isnt "" and answer.accepted? and answer.accepted isnt "" and
    answer.preToken? and answer.preToken isnt ""
        err = new Error "Bad request"
        err.status = 400
        return next err

    # Get the Sharing document thanks to its id
    db.get answer.shareID, (err, doc) ->
        return next err if err?

        # Get the answering target
        tmp = (t for t in doc.targets when t.url is answer.hostUrl)

        # If we had parenthesis around the comprehension above then it's an
        # array that is returned. Since we only want one element if the length
        # of the array isn't 1 then we have a problem
        unless tmp.length is 1
            err = new Error answer.hostUrl + " not found for this sharing"
            err.status = 404
            return next err

        # As explained in the comments above we only have one element, that we
        # extract in another variable for ease of use
        target = tmp[0]

        # Check if the preToken is correct
        if target.preToken isnt answer.preToken
            err = new Error "Unauthorized"
            err.status = 401
            return next err

        # The answer cannot be sent more than once
        if target.token?
            err = new Error "The answer for this sharing has already been given"
            err.status = 403
            return next err

        # The target has accepted the sharing : save the token
        if answer.accepted
            log.info "Sharing #{answer.shareID} accepted by #{target.url}"

            target.token = answer.token
            delete target.preToken
        # The target has refused the sharing : remove the target
        else
            log.info "Sharing #{answer.shareID} denied by #{target.url}"

            i = doc.targets.indexOf target
            doc.targets.splice i, 1

        # Update the Sharing doc
        db.merge doc._id, doc, (err, result) ->
            return next err if err?

            # Retrieve all the docIDs
            docIDs = (rule.id for rule in doc.rules)

            # Params structure for the replication
            replicate =
                target: target
                id: doc._id
                docIDs: docIDs
                continuous: doc.continuous

            req.replicate = replicate
            next()


# Replicate documents to the target url

# Params must contain:
#   id         -> the Sharing id, used as a login
#   target     -> contains the url and the token of the target
#   docIDs     -> the docIDs to replicate
#   continuous -> [optionnal] if the sharing is synchronous or not
module.exports.replicate = (req, res, next) ->
    replicate = req.replicate

    # Replicate only if the target has accepted, i.e. gave a token
    if replicate.target.token?
        Sharing.replicateDocs replicate, (err, repID) ->
            if err?
                next err
            # The repID is needed if continuous
            else if replicate.continuous and not repID?
                err = "Replication error"
                err.status = 500
                next err
            else
                # Update the target with the repID if the sharing is continuous
                if replicate.continuous
                    db.get replicate.id, (err, doc) ->
                        return next err if err?

                        # Find the target in the db
                        targetUrl = replicate.target.url
                        target = (t for t in doc.targets when \
                            t.url is targetUrl)
                         # Get index of the target and update it
                        i = doc.targets.indexOf target
                        doc.targets[i].repID = repID

                        db.merge replicate.id, doc, (err, result) ->
                            return next err if err?

                            res.status(200).send success: true
                else
                    res.status(200).send success: true

    else
        res.status(200).send success: true

# Stop current replications for each specified target
# Params must contain:
#   targets[]  -> Each target must have an url,  a repID and a token
module.exports.stopReplications = (req, res, next) ->
    share = req.share

    # Cancel the replication for all the targets
    async.each share.targets, (target, cb) ->
        if target.repID?
            Sharing.cancelReplication target.repID, (err) ->
                cb err
        else
            cb()
    , (err) ->
        next err

