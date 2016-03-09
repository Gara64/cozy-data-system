###
#
#       # How to run the tests:
#       ## Installing dependencies
#
#       ```bash
#       sudo npm install -g coffeetape faucet
#       ```
#
#       * coffeetape: coffeescript version of tape
#       * faucet: human-readable TAP summarizer
#
#       ## Running the tests
#
#       ``` bash
#       coffeetape controllers_sharing.coffee | faucet
#       ```
#
#       ## Troubleshooting
#
#       "[...] cannot find module 'tape'"
#
#       Locate your `node_modules` folder on your machine.
#       ```bash
#       find /usr/local -type d -name "node_modules"
#       ```
#
#       Export the global variable NODE_PATH
#       ```bash
#       export NODE_PATH=/usr/local/lib/node_modules
#       ```
#
###


test = require 'tape'
proxyquire = require 'proxyquire'

# -- Global variables
res = {}
res_err = {}
dbStorageStub = {}

# -- Mockups
# Create a mockup of the database
dbStub = {}
dbStub.save = (el, cb) ->
    res = { _id: 1 }
    err = null
    dbStorageStub = el
    cb err, res

# Create a mockup of the db_connect_helper
db_connectStub = {}
db_connectStub.db_connect =  ->
    return dbStub

# mockup of lib/sharing
sharingStub = {}
sharingStub.getDomain = (cb) ->
    err = err_no_domain
    cb err


sharing = proxyquire '../server/controllers/sharing',
    { '../helpers/db_connect_helper': db_connectStub },
    { '../lib/sharing': sharingStub }



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
    req.body.targets = [ {url: 'uneurl.fr'}, {url: ''} ]
    err = new Error "No url specified"
    err.status = 400

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if url is empty"

    # -- TEST 4
    # if body.rules doesn't exist, throw an error
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
    req.body.rules = [{id: '', docType: 'undoctype'}]
    err = new Error "Incorrect rule detected"
    err.status = 400

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if a rule is incorrect (id empty)"

    # -- TEST 7
    # if a rule is incorrect, throw an error => id missing
    req.body.rules = [{docType: 'undoctype'}]

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if a rule is incorrect (id missing)"

    # -- TEST 8
    # if a rule is incorrect, throw an error => docType missing
    req.body.rules = [{id: 'unid'}]

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.deepEqual res_err, err,
        "create: Return error if a rule is incorrect (docType missing)"

    # -- TEST 9 & 10
    # test that document stored has the doctype automatically set to "sharing"
    req.body.rules = [{id: 'unid', docType: 'undocType'}]

    sharing.create req, res, (_err) ->
        res_err = _err

    assert.error res_err, "create: function should not throw an error"

    req.body.docType = "sharing"
    assert.deepEqual dbStorageStub, req.body

    assert.end()





#test 'Testing `delete` module', (assert) ->

    ## -- TEST 1
    ## if params.id is missing an error is returned
    #req = { params: {} }

    #sharing.delete req, res, (err) ->
        #assert.deepEqual err, err_bad_request,
            #"delete: Return bad request error if params.id is missing"

    #assert.end()


#test 'Testing `notifyTargets` module', (assert) ->

    ## -- TEST 1
    ## if req.share is missing an error is returned
    #req = {}

    #sharing.notifyTargets req, res, (err) ->
        #assert.deepEqual err, err_bad_request,
            #"notifyTargets: Return bad request error if req.share is missing"

    ## -- TEST 2
    ## return an error if the domain was not found
    #req = { share: {} }
    #sharing.notifyTargets req, res, (err) ->
        #assert.deepEqual err, err_no_domain,
            #"notifyTargets: Return an error if domain is not set"

    # assert.end()
