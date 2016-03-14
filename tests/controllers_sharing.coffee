###

 # How to run the tests manually:
 ## Installing dependencies (globally)

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

# -- MOCKUPS / STUBS
# Create an empty stub of the database. It will be populated later on.
dbStub = {}

# Create a stub of the db_connect_helper
db_connectStub = {}
db_connectStub.db_connect =  ->
    return dbStub

# Through proxyquire tell sharing to use the mockups instead of the real
# functions
sharing = proxyquire '../server/controllers/sharing',
    { '../helpers/db_connect_helper': db_connectStub }


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
        assert.deepEqual _err, err,
            "create: Return error if body is empty"

    # -- TEST 2
    # if body.targets.length <= 0 a bad request error is returned
    req.body = {}
    req.body.targets = [{}]
    err = new Error "No target specified"
    err.status = 400

    sharing.create req, res, (_err) ->
        assert.deepEqual _err, err,
            "create: Return error if targets is empty"

    # -- TEST 3
    # if the url of a target is not specified throw an error
    req.body.targets = [ {url: 'uneurl.fr'}, {url: ''} ]
    err = new Error "No url specified"
    err.status = 400

    sharing.create req, res, (_err) ->
        assert.deepEqual _err, err,
            "create: Return error if url is empty"

    # -- TEST 4
    # if body.rules doesn't exist, throw an error
    req.body.targets = [ {url: 'uneurl.fr'} ]
    req.body.rules = []
    err = new Error "No rules specified"
    err.status = 400

    sharing.create req, res, (_err) ->
        assert.deepEqual _err, err,
            "create: Return error if rules is empty"

    # -- TEST 5
    # if a rule is incorrect, throw an error => docType empty
    req.body.targets = [ {url: 'uneurl.fr'} ]
    req.body.rules = [{id: 'unid', docType: ''}]
    err = new Error "Incorrect rule detected"
    err.status = 400

    sharing.create req, res, (_err) ->
        assert.deepEqual _err, err,
            "create: Return error if a rule is incorrect (docType empty)"

    # -- TEST 6
    # if a rule is incorrect, throw an error => id empty
    req.body.rules = [{id: '', docType: 'undoctype'}]
    err = new Error "Incorrect rule detected"
    err.status = 400

    sharing.create req, res, (_err) ->
        assert.deepEqual _err, err,
            "create: Return error if a rule is incorrect (id empty)"

    # -- TEST 7
    # if a rule is incorrect, throw an error => id missing
    req.body.rules = [{docType: 'undoctype'}]

    sharing.create req, res, (_err) ->
        assert.deepEqual _err, err,
            "create: Return error if a rule is incorrect (id missing)"

    # -- TEST 8
    # if a rule is incorrect, throw an error => docType missing
    req.body.rules = [{id: 'unid'}]

    sharing.create req, res, (_err) ->
        assert.deepEqual _err, err,
            "create: Return error if a rule is incorrect (docType missing)"

    # -- TEST 9
    # If body is correct no error is returned

    # First we populate the database stub with the functions that'll be called
    dbStorageStub = {} # will be used to check what is added in the database
    dbStub.save = (el, cb) ->
        res = { _id: 1 }
        err = null
        dbStorageStub = el
        cb err, res

    dbStub.get = (id, cb) ->
        err = null
        res = { targets: [{url: 'lala', preToken: 'hihi'}], desc: 'fake!' }
        cb err, res

    req.body.rules = [{id: 'unid', docType: 'undocType'}]

    sharing.create req, res, (_err) ->
        assert.error _err, "create: function should not throw an error"

    # -- TEST 10
    # Test that docType is automatically added and set to "sharing".
    # To do so we use the object we declared in the test above
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
    req = { params: {} }
    err = new Error "Bad request"
    err.status = 400

    sharing.delete req, res, (_err) ->
        assert.deepEqual _err, err,
            "delete: Return bad request error if params.id is missing"

    # -- TEST 2
    # if params is ok then db.remove function is called
    req.params.id = 1

    # we populate the database stub with the remove function and we check that
    # is it indeed called thanks to the dbStubWasRemoved boolean
    dbStubWasRemoved = false
    dbStub.remove = (id, cb) ->
        err = null
        res = {}
        dbStubWasRemoved = true
        cb err, res

    sharing.delete req, res, (_err) ->
        assert.ok dbStubWasRemoved,
            "delete: db.remove function is called if params is ok"

        # -- TEST 3
        # if params is ok no error is returned
        assert.error _err,
            "delete: no error is returned if params is ok"

    assert.end()


test 'Testing `handleRecipientAnswer` module', (assert) ->

    # -- TEST 1
    # return an error if body of request is missing
    req = {}
    err = new Error "Bad request"
    err.status = 400

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body is missing"


    # -- TEST 2
    # return an error if structure of body is incorrect => id is missing
    req.body = {
        #id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.id is missing"


    # -- TEST 3
    # return an error if structure of body is incorrect => id is empty
    req.body = {
        id: '',
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.id is empty"


    # -- TEST 4
    # return an error if structure of body is incorrect => shareID is missing
    req.body = {
        id: 0,
        #shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.shareID is missing"


    # -- TEST 5
    # return an error if structure of body is incorrect => shareID is empty
    req.body = {
        id: 0,
        shareID: '',
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.shareID is empty"


    # -- TEST 6
    # return an error if structure of body is incorrect => accepted is missing
    req.body = {
        id: 0,
        shareID: 1,
        #accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.accepted is
            missing"


    # -- TEST 7
    # return an error if structure of body is incorrect => accepted is empty
    req.body = {
        id: 0,
        shareID: 1,
        accepted: '',
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.accepted is empty"


    # -- TEST 8
    # return an error if structure of body is incorrect => url is missing
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        #url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.url is missing"


    # -- TEST 9
    # return an error if structure of body is incorrect => url is empty
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: '',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.url is empty"


    # -- TEST 10
    # return an error if structure of body is incorrect => hostUrl is missing
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}]
        #hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.hostUrl is missing"


    # -- TEST 11
    # return an error if structure of body is incorrect => hostUrl is empty
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: '' # me@localhost.me
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.hostUrl is empty"


    # -- TEST 12
    # return an error if structure of body is incorrect => rules is missing
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        #rules: [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.rules is missing"


    # -- TEST 13
    # return an error if structure of body is incorrect => rules is empty
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [], # [{id: 2, docType: 'event'}, {id: 3, docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.rules is empty"


    # -- TEST 14
    # return an error if structure of body is incorrect => rules[X].id is
    # missing
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {docType: 'event'}], # id: 3,
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.rules[X].id is
            missing"


    # -- TEST 15
    # return an error if structure of body is incorrect => rules[X].id is
    # empty
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: '', docType: 'event'}], #id: 3,
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.rules[X].id is
            empty"


    # -- TEST 16
    # return an error if structure of body is incorrect => rules[X].docType is
    # missing
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3}], # , docType: 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.rules[X].docType
            is missing"


    # -- TEST 17
    # return an error if structure of body is incorrect => rules[X].docType is
    # empty
    req.body = {
        id: 0,
        shareID: 1,
        accepted: true,
        url: 'foo@bar.baz',
        rules: [{id: 2, docType: 'event'}, {id: 3, docType: ''}], # 'event'}],
        hostUrl: 'me@localhost.me'
    }

    sharing.handleRecipientAnswer req, res, (_err) ->
        assert.deepEqual _err, err,
            "handleRecipientAnswer: return error if req.body.rules[X].docType
            is empty"

    assert.end()


test 'Testing `validateTarget` module', (assert) ->

    # -- TEST 1
    # an error is returned if req.body is missing
    err = new Error "Bad request"
    err.status = 400
    req = {}
    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if req.body is missing"

    # -- TEST 2
    # an error is returned if shareID is missing
    req.body = {
        #shareID: 1,
        hostUrl: 'foo@bar.baz',
        accepted: true,
        preToken: "preToken",
        token: "thisIsATokenForTheAuthenticationProcess"
    }

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if req.body.shareID is
            missing"

    # -- TEST 3
    # an error is returned if shareID is empty
    req.body = {
        shareID: '', #1,
        hostUrl: 'foo@bar.baz',
        accepted: true,
        preToken: "preToken",
        token: "thisIsATokenForTheAuthenticationProcess"
    }

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if req.body.shareID is
            empty"

    # -- TEST 4
    # an error is returned if hostUrl is missing
    req.body = {
        shareID: 1,
        #hostUrl: 'foo@bar.baz',
        accepted: true,
        preToken: "preToken",
        token: "thisIsATokenForTheAuthenticationProcess"
    }

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if req.body.hostUrl is
            missing"

    # -- TEST 5
    # an error is returned if hostUrl is empty
    req.body = {
        shareID: 1,
        hostUrl: '', #'foo@bar.baz',
        accepted: true,
        preToken: "preToken",
        token: "thisIsATokenForTheAuthenticationProcess"
    }

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if req.body.hostUrl is
            empty"

    # -- TEST 6
    # an error is returned if accepted is missing
    req.body = {
        shareID: 1,
        hostUrl: 'foo@bar.baz',
        #accepted: true,
        preToken: "preToken",
        token: "thisIsATokenForTheAuthenticationProcess"
    }

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if req.body.accepted is
            missing"

    # -- TEST 7
    # an error is returned if accepted is empty
    req.body = {
        shareID: 1,
        hostUrl: 'foo@bar.baz',
        accepted: '',#true,
        preToken: "preToken",
        token: "thisIsATokenForTheAuthenticationProcess"
    }

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if req.body.accepted is
            empty"

    # -- TEST 8
    # an error is returned if preToken is missing
    req.body = {
        shareID: 1,
        hostUrl: 'foo@bar.baz',
        accepted: true,
        #preToken: "preToken",
        token: "thisIsATokenForTheAuthenticationProcess"
    }

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if req.body.preToken is
            missing"

    # -- TEST 9
    # an error is returned if preToken is empty
    req.body = {
        shareID: 1,
        hostUrl: 'foo@bar.baz',
        accepted: true,
        preToken: '', #"preToken",
        token: "thisIsATokenForTheAuthenticationProcess"
    }

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if req.body.preToken is
            empty"

    # -- TEST 10
    # an error is returned if hostUrl isn't in the targets of share document
    req.body = {
        shareID: 1,
        hostUrl: 'foo@bar.baz',
        accepted: true,
        preToken: 'preToken',
        token: "thisIsATokenForTheAuthenticationProcess"
    }

    # Modifying dbStub for the test
    dbStub.get = (id, callback) ->
        doc =
            targets: [{url: 'random@mail.com', preToken: 'preToken'}]

        callback null, doc

    err = new Error "random@mail.com not found for this sharing"
    err.status = 404

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if hostUrl isn't in the
            targets of share document"

    # -- TEST 11
    # an error is returned if the preToken of the target and of the req.body
    # don't match
    dbStub.get = (id, callback) ->
        doc =
            targets: [{url: 'foo@bar.baz', preToken: 'surprise!'}]

        callback null, doc

    err = new Error "Unauthorized"
    err.status = 401

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if the preToken of the target
            and of the req.body don't match"

    # -- TEST 12
    # an error is returned if the token is already set for the target
    dbStub.get = (id, callback) ->
        doc =
            rules: [{id: 1, docType: 'event'}],
            targets: [{url: 'foo@bar.baz', preToken: 'preToken', token: 'set'}]

        callback null, doc

    err = new Error "The answer for this sharing has already been given"
    err.status = 403

    sharing.validateTarget req, res, (_err) ->
        assert.deepEqual _err, err,
            "validateTarget: an error is returned if the token is already set
            for the target"

    # -- TEST 13
    # preToken is deleted if target has accepted the request
    docDbStubMerge = {}
    preTokenDeleted = true

    dbStub.get = (id, callback) ->
        doc =
            rules: [{id: 1, docType: 'event'}],
            targets: [{url: 'foo@bar.baz', preToken: 'preToken'}]

        callback null, doc

    dbStub.merge = (repID, doc, callback) ->
        docDbStubMerge = doc # we get the document passed
        callback null

    sharing.validateTarget req, res, (_err) ->
        # we check that for each target the preToken is deleted
        for target in docDbStubMerge.targets
            if target.preToken?
                preTokenDeleted = false

        assert.ok preTokenDeleted,
            "validateTarget: preToken is deleted if target has accepted the
            request"

        # -- TEST 14
        # no error is returned if req.body is ok & accepted is true
        assert.error _err,
            "validateTarget: no error is returned if req.body is ok and
            accepted is true"

    # -- TEST 15
    # target is removed from share document if request was denied
    targetDeleted = true
    req.body = {
        shareID: 1,
        hostUrl: 'foo@bar.baz',
        accepted: false,
        preToken: 'preToken',
        token: "thisIsATokenForTheAuthenticationProcess"
    }

    sharing.validateTarget req, res, (_err) ->
        for target in docDbStubMerge.targets
            if target.url is req.body.hostUrl
                targetDeleted = false

        assert.ok targetDeleted,
            "validateTarget: target is removed from share document if request
            was denied"

        # -- TEST 16
        # no error is returned if req.body is ok and accepted is false
        assert.error _err,
            "validateTarget: no error is returned if req.body is ok and
            accepted is false"

    assert.end()
