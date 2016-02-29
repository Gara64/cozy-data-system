Sharing = require '../lib/sharing'
async = require 'async'

addAccess = require('../lib/token').addAccess
db = require('../helpers/db_connect_helper').db_connect()

# XXX Shouldn't we be using a dedicated library?
# Define random function for application's token
randomString = (length) ->
    string = ""
    while (string.length < length)
        string = string + Math.random().toString(36).substr(2)
    return string.substr 0, length


# --- Creation of the share document.
# The share document is a document that represents the sharing process that was
# initiated and that we store in the database for further use.
#
# The structure of a share document is as following
# shareDoc {
#   id        -> the id of the sharing process, it is generated when the
#                document is inserted in the database
#   desc      -> a description of what is shared
#   rules     -> a set of rules describing which documents will be shared
#                providing their id and their docType
#   targets[] -> an array containing the users to whom the documents will be
#                shared. This array contains "target" a custom structure that
#                will hold all the information required to share with that
#                particular user.
# }
#
# The structure target:
# target {
#   url           -> the url of the user's cozy
#   pwd           -> the password linked to the sharing process
#   replicationID -> the id generated by CouchDB for the replication. The
#                    replication is a process linked to Couch in order to
#                    replicate documents between Couch instances.
# }
#
# We suppose in this function that the data we receive is already in the
# correct format. That means we will receive a "share" object that has all its
# fields filled as needed.
module.exports.create = (req, res, next) ->
    # get a hold on the information
    share = req.body
    # check if the information is available
    if not share?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        # put the share document in the database
        db.save share, (err, res) ->
            if err?
                next err
            else
                share.id = res._id
                req.share = share
                next()


# Send a sharing request for each target defined in the share object
module.exports.requestTarget = (req, res, next) ->
    if not req.share?
        err = new Error "Bad request"
        err.status = 400
        next err
    else
        share = req.share
        Sharing.getDomain (err, domain) ->
            if err?
                next new Error 'No instance domain set'
            else
                request =
                    shareId: share.id
                    desc: share.desc
                    sync: share.sync
                    hostUrl: domain
                    rules: share.rules

                # XXX Debug
                console.log 'request : ' + JSON.stringify request

                # Notify each target
                async.each share.targets, (target, callback) ->
                    request.url = target.url
                    Sharing.notifyTarget target.url, request, (err, result, body) ->
                        if err?
                            callback err
                        else if not result?.statusCode?
                            err = new Error "Bad request"
                            err.status = 400
                            callback err
                        else
                            res.send result.statusCode, body
                            callback()

                , (err) ->
                    return next err if err?


# Create access if the sharing answer is yes, remove the UserSharing doc
# otherwise.
#
# The "sharing document" (or "UserSharing") is created when the request is
# received. This behavior was chosen for persistence: if we store it on RAM
# until the user validates then the request could be lost if the server
# reboots. It is not much of a problem since creating a document is much like
# receiving an e-mail.
#
# Params must contains :
#   * id        -> the id of the "sharing document" created when the share
#                  request was received -- RECEIVER SIDE
#   * shareID   -> the id of the "sharing document" created by the emitter --
#                  EMITTER SIDE
#   * accepted  -> boolean specifying if the share was accepted or not
#   * targetUrl -> the url of the cozy
#   * rules     -> the set of rules specifying exactly which documents are
#                  shared
#   * hostUrl   -> the url of the emitter's cozy
module.exports.handleAnswer = (req, res, next) ->

    if not req.body?
        err = new Error "Bad request"
        err.status = 400
        next err
    params = req.body

    # Create an access is the sharing is accepted
    if params.accepted is yes
        access =
            login: params.shareID
            # XXX Use custom library instead
            password: randomString 32
            id: params.id
            rules: params.rules

        addAccess access, (err, doc) ->
            return next err if err?

            params.pwd = access.password
            req.params = params
            next()

    # Delete the associated doc if the sharing is refused
    else
        db.remove req.params.id, (err, res) ->
            return next err if err?
            req.params = params
            next()


# Send the answer to the emitter of the share request
#
# Params must contain:
#   * shareID  -> the id of the "sharing document" generated by the emitter
#   * url      -> the url of the receiver's cozy
#   * accepted -> boolean telling if request was accepted/denied
#   * pwd      -> the password generated by the receiver if the request was
#                 accepted
#   * hostUrl  -> the url of the emitter's cozy
module.exports.sendAnswer = (req, res, next) ->

    # XXX DEBUG
    console.log 'params ' + JSON.stringify req.params

    params = req.body
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
                res.send result.statusCode, body


# Process the answer given by the target regarding the sharing request that was
# sent to him.
#
# The structure of the answer received is as following:
# answer {
#   shareID    -> the id of the sharing request
#   url        -> the url of the target
#   accepted   -> wether or not the target has accepted the request
#   pwd        -> the password generated by the target
# }
#
module.exports.validateTarget = (req, res, next) ->
    # XXX DEBUG
    console.log 'answer : ' + JSON.stringify req.body

    answer = req.body
    if not answer?
        # send an error explaining that the answer received has not the
        # expected format or just isn't there
        err = new Error "Bad request"
        err.status = 400
        next err

    else
        # we get a hold on the share document stored in the database that
        # represents this sharing process
        db.get answer.shareID, (err, doc) ->
            return next err if err?

            # Get the answering target
            target = t for t in doc.targets when t.url = answer.url
            if not target?
                err = new Error answer.url + " not found for this sharing"
                err.status = 404
                next err
            else
                # Check if the target has accepted the request. Add the
                # password to the target if accepted, remove the target
                # otherwise
                if answer.accepted
                    target.pwd = answer.pwd
                else
                    i = doc.targets.indexOf target
                    doc.targets.splice i, 1

                # Update db
                db.merge doc._id, doc, (err, res) ->
                    return next err if err?

                    # Params structure for the replication function
                    params =
                        pwd: answer.pwd
                        url: answer.url
                        id: doc._id
                        docIDs: doc.docIDs
                        sync: doc.sync

                    req.params = params
                    next()


module.exports.replicate = (req, res, next) ->
    params = req.params
    # Replicate on the validated target
    if params.pwd?
        Sharing.replicateDocs params, (err, repID) ->
            if err?
                next err
            else if not repID?
                err = new Error "Replication failed"
                err.status = 500
                next err
            # TODO : update the db
            if repID?
                res.send 200, success: true

    else
        res.send 200, success: true
