db = require('../helpers/db_connect_helper').db_connect()
async = require 'async'
request = require 'request-json'

# Get the Cozy url
getDomain = (callback) ->
    db.view 'cozyinstance/all', (err, instance) ->
        return callback err if err?

        if instance?[0]?.value.domain?
            domain = instance[0].value.domain
            domain = "https://#{domain}/" if not (domain.indexOf('http') > -1)
            callback null, domain
        else
            callback null

# Send a notification to a target url on the specified path
module.exports.notifyTarget = (path, params, callback) ->
    # Get the cozy url to let the target knows who is the sender
    getDomain (err, domain) ->
        if err? or not domain?
            callback new Error 'No instance domain set'
        else
            params.hostUrl = domain

            console.log 'request : ' + JSON.stringify params

            remote = request.createClient params.url
            remote.post path, params, (err, result, body) ->
                if err?
                    callback err
                else if not result?.statusCode?
                    err = new Error "Bad request"
                    err.status = 400
                    callback err
                else if body?.error?
                    err = body
                    err.status = result.statusCode
                    callback err
                else
                    callback()

# Share the ids to the specified target
module.exports.replicateDocs = (params, callback) ->
    unless params.target? and params.docIDs? and params.id?
        err = new Error 'Parameters missing'
        err.status = 400
        callback err
    else
        # Add the credentials in the url
        auth = params.id + ":" + params.target.token
        url = params.target.url.replace "://", "://" + auth + "@" 

        replication =
            source: "cozy"
            target: url + "/services/sharing/replication/" 
            continuous: params.continuous or false
            doc_ids: params.docIDs

        console.log 'params replication : ' + JSON.stringify replication

        db.replicate replication.target, replication, (err, body) ->
            if err? then callback err
            else if not body.ok
                err = "Replication failed"
                callback err
            else
                console.log JSON.stringify body
                # The _local_id field is returned only if continuous
                callback null, body._local_id

# Interrupt the running replication
module.exports.cancelReplication = (replicationID, callback) ->
    unless replicationID?
        err = new Error 'Parameters missing'
        err.status = 400
        callback err
    else
        cancel =
            replication_id: replicationID
            cancel: true

        db.replicate '', cancel, (err, body) ->
            if err?
                callback err
            else if not body.ok
                err = "Cancel replication failed"
                callback err
            else
                callback()
