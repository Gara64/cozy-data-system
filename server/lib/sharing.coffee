db = require('../helpers/db_connect_helper').db_connect()
replicator = require('../helpers/db_connect_helper').db_replicator_connect()
async = require 'async'
request = require 'request-json'
log = require('printit')
    prefix: 'sharing'
User = require './user'
user = new User()

replications = {}

# Contains all the sharing rules
# Avoid to request CouchDB for each document
rules = []



# ---------------------------- DEMO -----------------------

# Map the inserted document against all the sharing rules
# If one or several mapping are trigerred, the result {id, shareID, userParams}
# will be inserted in PlugDB as a Doc and/or a User
module.exports.evalInsert = (doc, id, callback) ->
    console.log 'doc insert : '  + JSON.stringify doc

    #Particular case for sharing rules
    if doc.docType is 'sharingrule'
        createRule doc, id, (err) ->
            callback err
    else
        mapDocInRules doc, id, (err, mapResults) ->
            # mapResults : [ doc: {docID, userID, shareID, userParams, binaries},
            #                user: {docID, userID, shareID, userParams, binaries}]
            return callback err if err?

            console.log 'map results : ' + JSON.stringify(mapResults)
            return callback err
            ###
            # Serial loop, to avoid parallel db access
            async.eachSeries mapResults, insertResults, (err) ->
                return callback err if err?

                console.log 'mapping results insert : ' + JSON.stringify mapResults
                matchAfterInsert mapResults, (err, acls) ->
                    #acl :
                    #console.log 'acls : ' + JSON.stringify acls

                    return callback err if err?
                    return callback null unless acls? and acls.length > 0


                    startShares acls, (err) ->
                        callback err
            ###


# For each rule, evaluates if the document is correctly filtered/mapped
# as a document and/or a user
mapDocInRules = (doc, id, callback) ->

    # Evaluate a rule for the doc
    evalRule = (rule, _callback) ->

        mapResult = {}

        # Save the result of the mapping
        saveResult = (id, shareID, userParams, binaries, isDoc) ->
            res = {}
            if isDoc then res.docID = id else res.userID = id
            res.shareID = shareID
            res.userParams = userParams
            res.binaries = binaries
            if isDoc then mapResult.doc = res else mapResult.user = res


        filterDoc = rule.filterDoc
        filterUser = rule.filterUser

        # Evaluate the doc filter
        mapDoc doc, id, rule.id, filterDoc, (isDocMaped) ->
            if isDocMaped
                console.log 'doc maped !! '
                binIds = getbinariesIds doc
                saveResult id, rule.id, filterDoc.userParam, binIds, true

            # Evaluate the user filter
            mapDoc doc, id, rule.id, filterUser, (isUserMaped) ->
                if isUserMaped
                    console.log 'user maped !! '
                    binIds = getbinariesIds doc
                    saveResult id, rule.id, filterUser.userParam, binIds, false

                #console.log 'map result : ' + JSON.stringify mapResult
                if not mapResult.doc? && not mapResult.user?
                    _callback null, null
                else
                    _callback null, mapResult

    # Evaluate all the rules
    # mapResults : [ {docID, userID, shareID, userParams} ]
    async.map rules, evalRule, (err, mapResults) ->
        # Convert to array and remove null results
        mapResults = Array.prototype.slice.call( mapResults )
        removeNullValues mapResults
        callback err, mapResults

# Generic map : evaluate the rule in the filter against the doc
mapDoc = (doc, docID, shareID, filter, callback) ->
    console.log "eval " + filter.rule
    console.log "on " + JSON.stringify(doc)
    if eval filter.rule
        callback true
    else
        callback false

removeNullValues = (array) ->
    if array?
        for i in [array.length-1..0]
            array.splice(i, 1) if array[i] is null

# Particular case at the doc evaluation where a new rule is inserted
createRule = (doc, id, callback) ->
    ###
    plug.insertShare id, doc.name, (err) ->
        if err?
            callback err
        else
    ###
    rule =
        _id: id
        name: doc.name
        filterDoc: doc.filterDoc
        filterUser: doc.filterUser
    saveRule rule
    console.log 'rule inserted'
    callback null


# Save the sharing rule in RAM
saveRule = (rule, callback) ->
    id = rule._id
    name = rule.name
    filterDoc = rule.filterDoc
    filterUser = rule.filterUser
    activeReplications = rule.activeReplications if rule.activeReplications
    rules.push {id, name, filterDoc, filterUser, activeReplications}


# Called at the DS initialization
module.exports.initRules = (callback) ->
    db.view 'sharingrule/all', (err, rules) ->
        return callback new Error("Error in view") if err?
        rules.forEach (rule) ->
            saveRule rule

        callback()

# ------------------------ END DEMO


# Add https in case the protocol is not specified in the url
addProtocol = (url) ->
    url = "https://" + url if url?.indexOf("://") is -1
    return url


# Called each time a change occurs in the _replicator db
onChange = (change) ->
    if replications[change.id]?
        cb = replications[change.id]
        delete replications[change.id]

        # Check the replication status
        replicator.get change.id, (err, doc) ->
            if err?
                cb err
            else if doc._replication_state is "error"
                err = "Replication failed"
                cb err
            else
                cb null, change.id


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


# Retrieve the domain if the url is not set, to avoid
# unacessary call and potential domain mismatch on the target side
checkDomain = (url, callback) ->
    unless url?
        # Get the cozy url to let the target knows who is the sender
        getDomain (err, domain) ->
            if err? or not domain?
                callback new Error 'No instance domain set'
            else
                callback err, domain
    else
        callback null, url


# Utility function to handle notifications responses
handleNotifyResponse = (err, result, body, callback) ->
    if err?
        callback err
    else if not result?.statusCode?
        err = new Error "Bad request"
        err.status = 400
        callback err
    else if body?.error?
        err = new Error body.error
        err.status = result.statusCode
        callback err
    else if result?.statusCode isnt 200
        err = new Error "The request has failed"
        err.status = result.statusCode
        callback err
    else
        callback()

# Send a notification to a recipient url on the specified path
# A successful request is expected to return a 200 HTTP status
module.exports.notifyRecipient = (url, path, params, callback) ->
    # Get the domain if not already set
    checkDomain params.sharerUrl, (err, domain) ->
        return err if err?
        params.sharerUrl = domain

        # Get the user name
        user.getUser (err, userInfos) ->
            return err if err?

            params.sharerName = userInfos.public_name
            # Avoid empty usernames
            if not params.sharerName? or (params.sharerName is '')
                params.sharerName = params.sharerUrl.replace "https://", ""

            # Add https if not specified
            url = addProtocol url
            # Send to recipient
            remote = request.createClient url
            remote.post path, params, (err, result, body) ->
                handleNotifyResponse err, result, body, callback


# Send a notification to a recipient url on the specified path
# A successful request is expected to return a 200 HTTP status
module.exports.notifySharer = (url, path, params, callback) ->
    # Get the domain if not already set
    checkDomain params.recipientUrl, (err, domain) ->
        return err if err?

        params.recipientUrl = domain
        remote = request.createClient url
        remote.post path, params, (err, result, body) ->
            handleNotifyResponse err, result, body, callback


# Send a revocation request to the specified url
module.exports.sendRevocation = (url, path, params, callback) ->
    # Add https if not specified
    url = addProtocol url
    remote = request.createClient url
    remote.del path, params, (err, result, body) ->
        handleNotifyResponse err, result, body, callback


# Replicate documents to the specified target
# Params must contain:
#   id         -> the Sharing id, used as a login
#   target     -> contains the url and the token of the target
#   docIDs     -> the ids of the documents to replicate
#   continuous -> [optionnal] if the sharing is synchronous or not
module.exports.replicateDocs = (params, callback) ->
    unless params.target? and params.docIDs? and params.id?
        err = new Error 'Parameters missing'
        err.status = 400
        callback err
    else
        # Add the credentials in the url
        auth = "#{params.id}:#{params.target.token}"
        url = addProtocol params.target.recipientUrl
        url = url.replace "://", "://#{auth}@"

        # Remove last slash in recipient's url
        if url.charAt(url.length - 1) is '/'
            url = url.substring(0, url.length - 1)

        couchCred = db.connection
        couch = [couchCred.host, couchCred.port]
        if couchCred.auth?
            couchAuth = "#{couchCred.auth.username}:#{couchCred.auth.password}"
            source = "http://#{couchAuth}@#{couch[0]}:#{couch[1]}/cozy"
        else
            source = "http://#{couch[0]}:#{couch[1]}/cozy"

        replication =
            source: source
            target: url + "/services/sharing/replication/"
            continuous: params.continuous or false
            doc_ids: params.docIDs


        # When a continuous replication is triggered, it must be saved in the
        # _relicator db to retrieve the connection even after a restart
        if replication.continuous
            replicator.save replication, (err, body) ->
                if err? then callback err
                else if not body.ok
                    err = "Replication failed"
                    callback err
                else
                    # The replication id and callback are needed when
                    # the changes feed is triggered
                    replications[body.id] = callback

        # The replication is not continuous : no need to keep it in db
        else
            db.replicate replication.target, replication, (err, body) ->
                if err? then callback err
                else if not body.ok
                    err = "Replication failed"
                    callback err
                else
                    callback null


# Interrupt the running replication
module.exports.cancelReplication = (replicationID, callback) ->
    unless replicationID?
        err = new Error 'Parameters missing'
        err.status = 400
        callback err
    else
        replicator.remove replicationID, (err) ->
            callback err


# Listen for a change on the replicator db, to know when a
# replication has been launched
changes = replicator.changes since: 'now'
changes.on 'change', onChange
changes.on 'error', (err) ->
    log.error "Replicator feed error : #{err.stack}"
