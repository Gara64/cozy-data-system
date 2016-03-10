###

 # How to run the tests:
 ## Installing dependencies

 ```bash
 sudo npm install -g coffeetape faucet
 ```

 * coffeetape: coffeescript version of tape
 * faucet: human-readable TAP summarizer

 ## Running the tests

 ``` bash
 coffeetape controllers_sharing.coffee | faucet
 ```

 ## Troubleshooting

 "[...] cannot find module 'tape'"

 Locate your `node_modules` folder on your machine.
 ```bash
 find /usr/local -type d -name "node_modules"
 ```

 Export the global variable NODE_PATH
 ```bash
 export NODE_PATH=/usr/local/lib/node_modules
 ```

###

test = require 'tape'
proxyquire = require 'proxyquire'


###############################################################################
#                            SETUP
###############################################################################

# -- GLOBAL VARIABLES
res = {}
res_err = {}


# -- MOCKUPS
# Create a mockup of the database
dbStub = {}
dbStorageStub = {}
dbStub.save = (el, cb) ->
    res = { _id: 1 }
    err = null
    dbStorageStub = el
    cb err, res

dbStub.get = (id, cb) ->
    err = null
    res = { targets: [{url: 'lala', preToken: 'hihi'}], desc: 'fake!' }
    cb err, res

dbStubWasRemoved = false
dbStub.remove = (id, cb) ->
    err = null
    res = {}
    dbStubWasRemoved = true
    cb err, res

# Create a mockup of the db_connect_helper
db_connectStub = {}
db_connectStub.db_connect =  ->
    return dbStub

# Mockup of lib/sharing
sharingStub = {}

sharingStubHostUrl = false
sharingStub.getDomain = (cb) ->
    sharingStubHostUrl = true
    console.log "DEBUG: getDomain called"
    err = null
    hostUrl = "localhost"
    cb err, hostUrl

sharingStubNotifyCount = 0
sharingStub.notifyTarget = (url, share, cb) ->
    sharingStubNotifyCount++
    sharingStubShare = share
    cb

# Mocking /lib/token addAccess function
libTokenStub = {}
accessAdded = false

libTokenStub.addAccess = (access, cb) ->
    console.log "DEBUG: addAccessFn"
    accessAdded = true
    doc = 'fake doc'
    err = null
    cb err, doc


# Through proxyquire tell sharing to use the mockups instead of the real
# functions
sharing = proxyquire '../server/controllers/sharing',
    { '../helpers/db_connect_helper': db_connectStub },
    { '../lib/sharing': sharingStub },
    { '../lib/token': libTokenStub }



###############################################################################
#                       TESTS
###############################################################################

test 'Testing `create` module', (assert) ->

    # -- TEST 1
    # Test if we pass an object that has no body the function returns an Error
    req = {}
    err = new Error "Bad request"
    err.status = 400
    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if body is empty"

    # -- TEST 2
    # if body.targets.length <= 0 a bad request error is returned
    res_err = null
    req.body = {}
    req.body.targets = [{}]
    err = new Error "No target specified"
    err.status = 400

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if targets is empty"

    # -- TEST 3
    # if the url of a target is not specified throw an error
    res_err = null
    req.body.targets = [ {url: 'uneurl.fr'}, {url: ''} ]
    err = new Error "No url specified"
    err.status = 400

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if url is empty"

    # -- TEST 4
    # if body.rules doesn't exist, throw an error
    res_err = null
    req.body.targets = [ {url: 'uneurl.fr'} ]
    req.body.rules = []
    err = new Error "No rules specified"
    err.status = 400

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if rules is empty"


    # -- TEST 5
    # if a rule is incorrect, throw an error => docType empty
    res_err = null
    req.body.targets = [ {url: 'uneurl.fr'} ]
    req.body.rules = [{id: 'unid', docType: ''}]
    err = new Error "Incorrect rule detected"
    err.status = 400

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if a rule is incorrect (docType empty)"

    # -- TEST 6
    # if a rule is incorrect, throw an error => id empty
    res_err = null
    req.body.rules = [{id: '', docType: 'undoctype'}]
    err = new Error "Incorrect rule detected"
    err.status = 400

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if a rule is incorrect (id empty)"

    # -- TEST 7
    # if a rule is incorrect, throw an error => id missing
    res_err = null
    req.body.rules = [{docType: 'undoctype'}]

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if a rule is incorrect (id missing)"

    # -- TEST 8
    # if a rule is incorrect, throw an error => docType missing
    res_err = null
    req.body.rules = [{id: 'unid'}]

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if a rule is incorrect (docType missing)"

    # -- TEST 9
    # If body is correct no error is returned
    res_err = null
    req.body.rules = [{id: 'unid', docType: 'undocType'}]

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.error res_err, "create: function should not throw an error"

    # -- TEST 10
    # Test that docType is automatically added and set to "sharing"
    req.body.docType = "sharing"
    assert.deepEqual dbStorageStub, req.body,
        "create: docType is automatically added and set to \"sharing\""

    # -- TEST 11
    # For each target a pre-token is generated
    hasPreToken = true
    for target in dbStorageStub.targets
        if not target.preToken? or target.preToken is ""
            hasPreToken = false

    assert.ok hasPreToken, "create: a pre-token is generated for each target"

    assert.end()


test 'Testing `delete` module', (assert) ->

    # -- TEST 1
    # if params.id is missing an error is returned
    res_err = null
    req = { params: {} }
    err = new Error "Bad request"
    err.status = 400

    sharing.delete req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "delete: Return bad request error if params.id is missing"

    # -- TEST 2
    # if params is ok then db.remove function is called
    res_err = null
    req.params.id = 1
    sharing.delete req, res, (_err) ->
        res_err = _err

    assert.ok dbStubWasRemoved,
        "delete: db.remove function is called if params is ok"

    # -- TEST 3
    # if params is ok no error is returned
    assert.error res_err,
        "delete: no error is returned if params is ok"

    assert.end()


test 'Testing `notifyTargets` module', (assert) ->

    # -- TEST 1
    # if req.share is missing an error is returned
    res_err = null
    req = {}
    err = new Error "Bad request"
    err.status = 400

    sharing.notifyTargets req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "notifyTargets: Return bad request error if req.share is missing"

    # -- TEST 2
    # return an error if the shareID is missing
    res_err = null
    req = { share: {} }
    err = new Error "No shareID provided"
    err.status = 400

    sharing.notifyTargets req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "notifyTargets: return an error if shareID is missing"

    # -- TEST 3
    # return an error if the shareID is empty
    res_err = null
    req.share.shareID = ""

    sharing.notifyTargets req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "notifyTargets: return an error if shareID is empty"

    # -- TEST 4
    # return an error if targets is missing
    res_err = null
    req.share.shareID = 1
    err = new Error "No target provided"
    err.status = 400

    sharing.notifyTargets req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "notifyTargets: return an error if targets is missing"

    # -- TEST 5
    # return an error if a target object is incorrect => target.url missing
    res_err = null
    req.share.targets = [{url: 'hey@hey.fr', preToken: 'hahaha'},
                         {preToken: 'hihihi'}]
    err = new Error "Incorrect target structure detected"
    err.status = 400

    sharing.notifyTargets req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "notifyTargets: return an error if target.url is missing"

    # -- TEST 6
    # return an error if a target object is incorrect => target.url empty
    res_err = null
    req.share.targets = [{url: 'hey@hey.fr', preToken: 'hahaha'},
                         {url: '', preToken: 'hihihi'}]

    sharing.notifyTargets req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "notifyTargets: return an error if target.url is empty"

    # -- TEST 7
    # return an error if a target object is incorrect => target.preToken
    # missing
    res_err = null
    req.share.targets = [{url: 'hey@hey.fr', preToken: 'hahaha'},
                         {url: 'yo@yo.fr'}]

    sharing.notifyTargets req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "notifyTargets: return an error if target.preToken is missing"

    # -- TEST 8
    # return an error if a target object is incorrect => target.preToken empty
    res_err = null
    req.share.targets = [{url: 'hey@hey.fr', preToken: 'hahaha'},
                         {url: 'yo@yo.fr', preToken: ''}]

    sharing.notifyTargets req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "notifyTargets: return an error if target.preToken is empty"

    # -- TEST 9
    # test that no error is returned if share object is ok
    res_err = null
    sharingStubNotifyCount = 0 # reset counter for TEST 11
    req.share.targets = [{url: 'hey@hey.fr', preToken: 'hahaha'},
                         {url: 'yo@yo.fr', preToken: 'hihihi'}]

    sharing.notifyTargets req, res, (_err) ->
        res_err = _err

    assert.error res_err,
        "notifyTargets: no error is returned if share object is ok"

    ## -- TEST 10
    ## test that hostUrl is added to share object transmitted to targets
    #assert.ok sharingStubHostUrl,
        #"notifyTargets: hostUrl is added to share object transmitted"

    ## -- TEST 11
    ## test that we call the function notifyTarget for each target
    #assert.equal sharingStubNotifyCount, req.share.targets.length,
        #"notifyTargets: function notifyTarget called for each target"

    assert.end()


test 'Testing `handleRecipientAnswer` module', (assert) ->

    # -- TEST 1
    # return an error if body of request is missing
    res_err = null
    req = {}
    err = new Error "Bad request"
    err.status = 400

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error if req.body is missing"

    # -- TEST 2
    # return an error if structure of body is incorrect => id is missing
    res_err = null
    req.body = {
        #id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.id is missing"

    # -- TEST 3
    # return an error if structure of body is incorrect => id is empty
    res_err = null
    req.body = {
        id: '',
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.id is empty"

    # -- TEST 4
    # return an error if structure of body is incorrect => shareID is missing
    res_err = null
    req.body = {
        id: 0,
        #shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.shareID is missing"

    # -- TEST 5
    # return an error if structure of body is incorrect => shareID is empty
    res_err = null
    req.body = {
        id: 0,
        shareID: '',
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.shareID is empty"

    # -- TEST 6
    # return an error if structure of body is incorrect => accepted is missing
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        #accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.accepted is missing"

    # -- TEST 7
    # return an error if structure of body is incorrect => accepted is empty
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: '',
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.accepted is empty"

    # -- TEST 8
    # return an error if structure of body is incorrect => url is missing
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        #url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.url is missing"

    # -- TEST 9
    # return an error if structure of body is incorrect => url is empty
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: '',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.url is empty"

    # -- TEST 10
    # return an error if structure of body is incorrect => hostUrl is missing
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        #hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.hostUrl is missing"

    # -- TEST 11
    # return an error if structure of body is incorrect => hostUrl is empty
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: '' # me@localhost.me
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.hostUrl is empty"

    # -- TEST 12
    # return an error if structure of body is incorrect => rules is missing
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        #rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.rules is missing"

    # -- TEST 13
    # return an error if structure of body is incorrect => rules is empty
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [], # [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.rules is empty"

    # -- TEST 14
    # return an error if structure of body is incorrect => rules[X].id is
    # missing
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {docType: 'event'}], # id: 3,
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.rules[X].id is missing"

    # -- TEST 15
    # return an error if structure of body is incorrect => rules[X].id is
    # empty
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: '', docType: 'event'}], # id: 3,
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.rules[X].id is empty"

    # -- TEST 16
    # return an error if structure of body is incorrect => rules[X].docType is
    # missing
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3}], # , docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.rules[X].docType is missing"

    # -- TEST 17
    # return an error if structure of body is incorrect => rules[X].docType is
    # empty
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: ''}], # 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "handleRecipientAnswer: return error is req.body.rules[X].docType is empty"

    # -- TEST 18
    # no error is returned if req.body has the correct structure
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.error res_err,
        "handleRecipientAnswer: no error is returned if req.body is ok"

    # -- TEST 19
    # an access is created if req.body.accepted is set to true
    res_err = null
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        res_err = _err

    assert.ok accessAdded,
        "handleRecipientAnswer: an access is generated if req.body.accepted is true"

    assert.end()
