db = require('../helpers/db_connect_helper').db_connect()
async = require 'async'
request = require 'request-json'

# Get the Cozy url
module.exports.getDomain = (callback) ->
    db.view 'cozyinstance/all', (err, instance) ->
        return callback err if err?

        if instance?[0]?.value.domain?
            domain = instance[0].value.domain
            domain = "https://#{domain}/" if not (domain.indexOf('http') > -1)
            callback null, domain
        else
            callback null


# Send a sharing request to a target
module.exports.notifyTarget = (targetURL, params, callback) ->
    remote = request.createClient targetURL
    remote.post "sharing/request", params, (err, result, body) ->
        console.log 'body : ' + JSON.stringify body
        callback err, result, body

# Send a sharing answer to a host
module.exports.answerHost = (hostURL, answer, callback) ->
    remote = request.createClient hostURL
    remote.post "sharing/answer", answer, (err, result, body) ->
        #console.log 'body : ' + JSON.stringify body
        callback err, result, body

# Share the ids to the specified target
module.exports.replicateDocs = (params, callback) ->

    console.log 'params : ' + JSON.stringify params

    unless params.target? and params.docIDs? and params.id?
        err = new Error 'Parameters missing'
        err.status = 400
        callback err

    console.log 'target : ' + JSON.stringify params.target
    console.log 'url : ' + JSON.stringify params.target.url
    # Add the credentials in the url
    auth = params.id + ":" + params.target.pwd
    url = params.target.url.replace "://", "://" + auth + "@" 

    replication =
        source: "cozy"
        target: url + "/sharing/replication/" 
        continuous: params.sync or false
        doc_ids: params.docIDs

    console.log 'rep data : ' + JSON.stringify replication
    
    db.replicate replication.target, replication, (err, res) ->
        if err? then callback err
        else
            console.log JSON.stringify res
            callback null, res

# Interrupt the running replication
module.exports.cancelReplication = (replicationID, callback) ->
    couchClient = request.createClient "http://localhost:5984"
    args =
        replication_id: replicationID
        cancel: true
    console.log 'cancel args ' + JSON.stringify args

    couchClient.post "_replicate", args, (err, res, body) ->
        if err?
            callback err
        else if not body.ok
            err = "Cancel replication failed"
            callback err
        else
            callback()


# Update the sharing doc on the activeReplications field
updateActiveRep = (shareID, activeReplications, callback) ->

    db.get shareID, (err, doc) ->
        return callback err if err?
        # Overwrite the activeReplication field,
        # if it exists or not in the doc
        # Note that a merge would be more efficient in case of existence
        # but less easy to deal with
        doc.activeReplications = activeReplications
        console.log 'active rep : ' + JSON.stringify activeReplications
        db.save shareID, doc, (err, res) ->
            callback err

# Write the replication id in the sharing doc and save in RAM
saveReplication = (rule, userID, replicationID, pwd, callback) ->
    return callback null unless rule? and replicationID?


    console.log 'save replication ' + replicationID + ' with userid ' + userID
    console.log 'pwd : ' + pwd

    if rule.activeReplications?.length > 0
        isUpdate = false
        async.each rule.activeReplications, (rep, _callback) ->
            # Update repID if userID already exists
            if rep?.userID == userID
                rep.replicationID = replicationID
                isUpdate = true

            _callback null

        , (err) ->
            console.log 'is update : ' + isUpdate
            # insert a new replication if the userID didn't exist before
            if not isUpdate
                rule.activeReplications.push {userID, replicationID, pwd}

            updateActiveRep rule.id, rule.activeReplications, (err) ->
                callback err
    else
        rule.activeReplications = [{userID, replicationID, pwd}]
        updateActiveRep rule.id, rule.activeReplications, (err) ->
            callback err


# TODO : remove this : Deprecated
# Remove the replication from RAM and DB
removeReplication = (rule, replicationID, userID, callback) ->
    # Cancel the replication for couchDB
    return callback null unless rule? and replicationID?

    cancelReplication replicationID, (err) ->
        return callback err if err?

        # There are active replications
        if rule.activeReplications?
            async.each rule.activeReplications, (rep, _callback) ->
                if rep?.userID == userID
                    i = rule.activeReplications.indexOf rep
                    rule.activeReplications.splice i, 1 if i > -1
                    updateActiveRep rule.id, rule.activeReplications, (err) ->
                        _callback err
                else
                    _callback null
            , (err) ->
                callback err
        # There is normally no replication written in DB, but check it
        # anyway to avoid ghost data
        else
            updateActiveRep rule.id, [], (err) ->
                callback err




       

getbinariesIds= (doc) ->
    if doc.binary?
        ids = (val.id for bin, val of doc.binary)
        #console.log 'binary ids : ' + JSON.stringify ids
        return ids

binaryHandling = (mapRes, callback) ->
    # TODO : handle this case :
    # The doc already had binaries : check previous ones in plugdb
    # and update it : retrieve previous ids in binary.coffee
    # beware to handle sequentials select properly

    if mapRes.doc.binaries? or mapRes.user.binaries?
        console.log 'go insert binaries'

        insertResults mapRes, (err) ->
            return callback err if err?

            matching mapRes, (err, acls) ->
                return callback err if err?
                return callback null unless acls?

                startShares [acls], (err) ->
                    callback err


    # This is not normal and probably an error in the execution order
    else
        console.log 'no binary in the doc'
        callback null

# Get the current replications ids
getActiveTasks = (client, callback) ->
    client.get "_active_tasks", (err, res, body) ->
        if err? or not body.length?
            callback err
        else
            for task in body
                repIds = task.replication_id if task.replication_id
            callback null, repIds

