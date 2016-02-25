db = require('../helpers/db_connect_helper').db_connect()
fs = require 'fs'
log = require('printit')
    prefix: 'token'
permissions = {}
tokens = {}
# Array of objects containing the rules describing which files can be accessed
# by which application.
# A rule is: {id: 'someId', docType: 'someDocType'}
# For a given app its set of rules can be retrieved via: sharing[app]
sharing = {}

productionOrTest = process.env.NODE_ENV in ['production', 'test']


## function checkToken (auth, tokens, callback)
## @auth {string} Field 'authorization' of request
## @tokens {tab} Tab which contains applications and their tokens
## @callback {function} Continuation to pass control back to when complete.
## Check if application is well authenticated
checkToken = module.exports.checkToken = (auth) ->
    if auth isnt "undefined" and auth?
        # Recover username and password in field authorization
        auth = auth.substr(5, auth.length - 1)
        auth = new Buffer(auth, 'base64').toString('ascii')
        username = auth.split(':')[0]
        password = auth.split(':')[1]
        # Check if application is well authenticated
        if password isnt undefined and tokens[username] is password
            return [null, true, username]
        else
            return [null, false, username]
    else
        return [null, false, null]


## function checkDocType (docType, app, callback)
## @docType {String} document's docType that application want manage
## @name {String} application's name
## @callback {function} Continuation to pass control back to when complete.
## Check if application can manage docType
module.exports.checkDocType = (auth, docType, callback) ->
    # Check if application is authenticated

    if productionOrTest
        [err, isAuthenticated, name] = checkToken auth
        if isAuthenticated
            if docType?
                docType = docType.toLowerCase()
                # Check if application can manage docType
                if permissions[name][docType]?
                    callback null, name, true
                else if permissions[name]["all"]?
                    callback null, name, true
                else
                    callback null, name, false
            else
                callback null, name, true
        else
            callback null, false, false
    else
        [err, isAuthenticated, name] = checkToken auth
        name ?= 'unknown'
        callback null, name, true


# Utility function to check if a rule is inside a set of rules.
# A rule has the following structure:
# rule = {id: 'someId', docType: 'someDocType'}
isRuleIn = (set_rules, rule) ->
    # check if `set_rules` is an array
    if set_rules.length?
        for _rule in set_rules
            if rule.id is _rule.id
                if rule.docType is _rule.docType
                    return true

        return false
    else
        # `set_rules` is a single element
        return set_rules.id is rule.id and set_rules.docType is rule.docType

# XXX WIP - to double-check
#
## function checkDocRule (auth, rule, callback)
## @auth {Object} the application means of authentication
## @rule {Object} the rule matching a unique document
## @callback {function} continuation
## Check if an application can manage the document matching the rule
module.exports.checkDocRule = (auth, rule, callback) ->

    if productionOrTest
        # Check if app is authenticated
        [err, isAuthenticated, name] = checkToken auth

        if isAuthenticated
            if rule?
                if isRuleIn sharing[name], rule
                    # rule is in: okay!
                    callback null, name, true
                else
                    # rule is missing: no way in!
                    callback null, name, false

            else
                # no rule? no way in!
                callback null, name, false
        else
            # app is not authenticated: no way in!
            callback null, false, false

    else
        [err, isAuthenticated, name] = checkToken auth
        name ?= 'unknow sharing'
        callback null, name, true


## function checkDocType (docType, app, callback)
## @docType {String} document's docType that application want manage
## @name {String} application's name
## @callback {function} Continuation to pass control back to when complete.
## Check if application can manage docType
module.exports.checkDocTypeSync = (auth, docType, callback) ->
    # Check if application is authenticated

    if productionOrTest
        [err, isAuthenticated, name] = checkToken auth
        if isAuthenticated
            if docType?
                docType = docType.toLowerCase()
                # Check if application can manage docType
                if permissions[name][docType]?
                    callback null, name, true
                else if permissions[name]["all"]?
                    return [null, name, true]
                else
                    return [null, name, false]
            else
                return [null, name, true]
        else
            return [null, false, false]
    else
        [err, isAuthenticated, name] = checkToken auth
        name ?= 'unknown'
        return [null, name, true]

## function checkProxy (auth, callback)
## @auth {String} Field 'authorization' i request header
##     Contains application name and password
## @callback {function} Continuation to pass control back to when complete.
## Check if application is proxy
## Useful for register and login requests
module.exports.checkProxyHome = (auth, callback) ->
    if productionOrTest
        if auth isnt "undefined" and auth?
            # Recover username and password in field authorization
            auth = auth.substr(5, auth.length - 1)
            auth = new Buffer(auth, 'base64').toString('ascii')
            username = auth.split(':')[0]
            password = auth.split(':')[1]
            # Check if application is cozy-proxy
            if password isnt undefined and tokens[username] is password
                if username is "proxy" or username is "home"
                    callback null, true
                else
                    callback null, false
            else
                callback null, false
        else
            callback null, false
    else
        callback null, true


# XXX WIP - to double-check
## function updatePermissons (access, callback)
## @access {Object} application:
##   * access.password is application token
##   * access.name is application name
##   * access.permissions is application permissions
##   * access.sharing is a set of {id: 'docId', docType: 'docType'} rules for
##     accessing documents.
## @callback {function} Continuation to pass control back to when complete.
## Update application permissions and token
updatePermissions = (access, callback) ->
    login = access.login

    if productionOrTest
        if access.token?
            tokens[login] = access.token

        if access.permissions?
            permissions[login] = {}
            for docType, description of access.permissions
                permissions[login][docType.toLowerCase()] = description

        if access.sharing?
            sharing[login] = access.sharing

        callback() if callback?

    else
        callback() if callback?


# XXX WIP - to double-check
## function addAccess (doc, callback)
## @doc {Object} application/device:
##   * doc.password is application token
##   * doc.slug/doc.login is application name
##   * doc.permissions is application permissions
##   * doc.id/doc._id is application id
##   * doc.sharing is a set of {'docId', 'docType'} rules for accessing
##     documents.
## @callback {function} Continuation to pass control back to when complete.
## Add access for application or device
addAccess = module.exports.addAccess = (doc, callback) ->

    # Create access
    access =
        docType: "Access"
        login: doc.slug or doc.login
        token: doc.password
        app: doc.id or doc._id

    # Safeguard: if we create an access that has sharing capabilities then its
    # permissions must be empty so that it can only access documents based on
    # the sharing "rules"
    if doc.sharing?
        access.sharing = doc.sharing
    else
        access.permissions = doc.permissions

    db.save access, (err, doc) ->
        log.error err if err?
        # Update permissions in RAM
        updatePermissions access, ->
            callback null, access if callback?


# XXX WIP - to double-check
## function updateAccess (doc, callback)
## @id {String} access id for application
## @doc {Object} application/device:
##   * doc.password is new application token
##   * doc.slug/doc.login is new application name
##   * doc.permissions is new application permissions
##   * doc.sharing is new set of sharing rules
## @callback {function} Continuation to pass control back to when complete.
## Update access for application or device
module.exports.updateAccess = (id, doc, callback) ->
    db.view 'access/byApp', key:id, (err, accesses) ->
        if accesses.length > 0
            access = accesses[0].value

            # Delete old access
            # XXX What happens if permissions[access.login] or
            # sharing[access.login] does not exist? Because if one does then
            # the other doesn't.
            delete permissions[access.login]
            delete tokens[access.login]
            delete sharing[access.login]

            # Create new access
            access.login = doc.slug or access.login
            access.token = doc.password or access.token
            if doc.sharing?
                access.sharing = doc.sharing
            else
                access.permissions = doc.permissions or access.permissions

            db.save access._id, access, (err, body) ->
                log.error err if err?
                # Update permissions in RAM
                updatePermissions access, ->
                    callback null, access if callback?
        else
            addAccess doc, callback


# XXX WIP - to double-check
## function removeAccess (doc, callback)
## @doc {Object} access to remove
## @callback {function} Continuation to pass control back to when complete.
## Remove access for application or device
module.exports.removeAccess = (doc, callback) ->
    db.view 'access/byApp', key:doc._id, (err, accesses) ->
        return callback err if err? and callback?
        if accesses.length > 0
            access = accesses[0].value
            # XXX Same as the above function: what happens when we try to
            # delete something that does not exist?
            delete permissions[access.login]
            delete tokens[access.login]
            delete sharing[access.login]
            db.remove access._id, access._rev, (err) ->
                callback err if callback?
        else
            callback() if callback?

## function initHomeProxy (callback)
## @callback {function} Continuation to pass control back to when complete
## Initialize tokens and permissions for Home and Proxy
initHomeProxy = (callback) ->
    token = process.env.TOKEN
    token = token.split('\n')[0]
    # Add home token and permissions
    tokens['home'] = token
    permissions.home =
        "application": "authorized"
        "access": "authorized"
        "notification": "authorized"
        "photo": "authorized"
        "file": "authorized"
        "background": "authorized"
        "folder": "authorized"
        "contact": "authorized"
        "album": "authorized"
        "message": "authorized"
        "binary": "authorized"
        "user": "authorized"
        "device": "authorized"
        "alarm": "authorized"
        "event": "authorized"
        "userpreference": "authorized"
        "cozyinstance": "authorized"
        "encryptedkeys": "authorized"
        "stackapplication": "authorized"
        "send mail to user": "authorized"
        "send mail from user": "authorized"
        "sharing": "authorized"
    # Add proxy token and permissions
    tokens['proxy'] = token
    permissions.proxy =
        "access": "authorized"
        "application": "authorized"
        "user": "authorized"
        "cozyinstance": "authorized"
        "device": "authorized"
        "usetracker": "authorized"
        "send mail to user": "authorized"
        "sharing": "authorized"
    callback null


## function initAccess (callback)
## @access {Object} Access
## @callback {function} Continuation to pass control back to when complete
## Initialize tokens and permissions for all accesses (applications or devices)
initAccess = (access, callback) ->
    name = access.login
    tokens[name] = access.token
    if access.permissions? and access.permissions isnt null
        permissions[name] = {}
        for docType, description of access.permissions
            docType = docType.toLowerCase()
            permissions[name][docType] = description
    if access.sharing?
        sharing[name] = access.sharing
    callback null

## function init (callback)
## @callback {function} Continuation to pass control back to when complete.
## Initialize tokens which contains applications and their tokens
module.exports.init = (callback) ->
    # Read shared token
    if productionOrTest
        initHomeProxy ->
            # Add token and permissions for other started applications
            db.view 'access/all', (err, accesses) ->
                return callback new Error("Error in view") if err?
                # Search application
                accesses.forEach (access) ->
                    initAccess access, ->
                callback tokens, permissions
    else
        callback tokens, permissions
