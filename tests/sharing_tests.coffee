should = require('chai').Should()
helpers = require('./helpers')
sinon = require 'sinon'
_ = require 'lodash'


db = require("#{helpers.prefix}server/helpers/db_connect_helper").db_connect()
sharing = require "#{helpers.prefix}server/controllers/sharing"
Sharing = require "#{helpers.prefix}server/lib/sharing"
libToken = require "#{helpers.prefix}server/lib/token"


client = helpers.getClient()
client.setBasicAuth "home", "token"


describe "Sharing controller tests:", ->

    before helpers.clearDB db
    before (done) ->
        helpers.startApp(done)

    after (done) ->
        helpers.stopApp(done)


    describe "create module", ->

        # Correct sharing structure
        share =
            desc: 'description'
            rules: [ {id: 1, docType: 'event'}, {id: 2, docType: 'Tasky'} ]
            targets: [{url: 'url1.com'}, {url: 'url2.com'}, \
                {url: 'url3.com'}]
            continuous: true


        # Tests with wrong parameters
        it 'should return a bad request if the body is empty', (done) ->
            data = {}
            client.post 'services/sharing/', data, (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal 'Bad request: no body'
                done()

        it 'should return a bad request if no target is specified', (done) ->
            data = _.clone share
            data.targets = []
            client.post 'services/sharing/', data, (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal 'No target specified'
                done()

        it 'should return a bad request if a target does not have an url',
        (done) ->
            data = _.clone share
            data.targets = [{url: 'url1.com'}, {url: 'url2.com'},
                {url : ''}]

            client.post 'services/sharing/', data, (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal 'No url specified'
                done()

        it 'should return a bad request if no rules are specified', (done) ->
            data = _.clone share
            data.rules = []
            client.post 'services/sharing/', data, (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal 'No rules specified'
                done()

        it 'should return a bad request if a rule does not have an id',
        (done) ->
            data = _.clone share
            data.rules = [{id: 1, docType: 'event'}, \
                          {id: '', docType: 'Tasky'}]
            client.post 'services/sharing/', data, (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal 'Incorrect rule detected'
                done()

        it 'should return a bad request if a rule does not have a docType',
        (done) ->
            data = _.clone share
            data.rules = [{id: 1, docType: 'event'}, {id: 2}]
            client.post 'services/sharing/', data, (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal 'Incorrect rule detected'
                done()

        it 'should set the shareID, the docType to "sharing" and generate
        preTokens', (done) ->
            req = body: _.clone share
            res = {}
            sharing.create req, res, ->
                req.share.should.exist
                req.share.shareID.should.exist
                req.share.docType.should.equal "sharing"
                for target in req.share.targets
                    should.exist(target.preToken)
                done()


    describe 'sendSharingRequests module', ->

        # Correct sharing structure normally obtained as a result of `create`
        share =
            desc: 'description'
            docType: 'sharing'
            shareID: '1aqwzsx'
            rules: [ {id: 1, docType: 'event'}, {id: 2, docType: 'Tasky'} ]
            targets: [{url: 'url1.com', preToken: 'preToken1'}, \
                {url: 'url2.com', preToken: 'preToken2'}, \
                {url: 'url3.com', preToken: 'preToken3'}]
            continuous: true

        # Spies on the parameters given to the `notifyTarget` module
        spyRoute = {}
        spyRequest = {}

        # We stub the `notifyTarget` module to avoid calling it (if so it would
        # try to request the url we declare in the share object).
        stubFn = (route, request, callback) ->
            spyRoute = route
            spyRequest = request
            callback null # to mimick success
        notifyStub = {}

        beforeEach (done) ->
            notifyStub = sinon.stub Sharing, "notifyTarget", stubFn
            done()

        afterEach (done) ->
            notifyStub.restore()
            done()


        it 'should send a request to all targets', (done) ->
            req = share: _.clone share

            # XXX This is ugly...is there a better way? (or is it not ugly?)
            #
            # The last call issued by the `sendSharingRequests` module is
            # `res.status(200).send success: true` which is Express logic. That
            # means that there is a hidden `next` callback, somewhere. Since
            # for the purpose of the test we don't want said callback to take
            # place we have to stub it. But that's not all: we also have to
            # find a way to mimic the `next` callback. That is why the `done()`
            # is inserted here, preceeded by the test. It is this `done()` that
            # is actually called and not the one in the sendSharingRequests if
            # everything goes well.
            resStub =
                status: (_) ->
                    send: (_) ->
                        notifyStub.callCount.should.equal share.targets.length
                        done()

            sharing.sendSharingRequests req, resStub, ->
                done()

        it 'should define a correct request', (done) ->
            req = share: _.clone share

            # XXX That's probably is ugly
            # stub `res.status(200).send success:true` call
            resStub =
                status: (_) ->
                    send: (_) ->
                        # XXX I cannot get this to work so...
                        #spyRequest.should.have.all.keys(['url', 'preToken',
                            #'shareID', 'rules', 'desc'])
                        # ... I test everything separatly. Since there are 3
                        # targets spyRequest should only contain the url of the
                        # third target
                        should.exist(spyRequest)
                        spyRequest.url.should.equal 'url3.com'
                        spyRequest.preToken.should.equal 'preToken3'
                        spyRequest.shareID.should.equal req.share.shareID
                        spyRequest.rules.should.deep.equal req.share.rules
                        spyRequest.desc.should.equal req.share.desc

                        done()

            sharing.sendSharingRequests req, resStub, ->
                done()

        it 'should send the requests on services/sharing/request', (done) ->
            req = share: _.clone share
            # we only let one target: spyRoute is set with it
            req.share.targets = [{url: 'url1.com', preToken: 'preToken1'}]

            # XXX Once again it kinda is ugly...
            # stub `res.status(200).send success:true` call
            #
            # Here not only do we stub the Express logic but we also make a
            # test on a global variable `spyRoute` that was declared at the
            # beginning of the `describe` block. I guess it could be done in a
            # more elegant manner but I don't know how (just yet).
            resStub =
                status: (_) ->
                    send: (_) ->
                        spyRoute.should.equal 'services/sharing/request'
                        done()

            sharing.sendSharingRequests req, resStub, ->
                done()

        it 'should return an error if notifyTarget failed', (done) ->
            # remove previously defined stub...
            notifyStub.restore()
            # ... and generate a new one that mimicks failure
            stubFn = (route, request, callback) ->
                callback "Error" # to mimick failure we return something
            notifyStub = sinon.stub Sharing, "notifyTarget", stubFn

            # We want a correct structure
            req = share: _.clone share
            res = {} # no need to mimic Express since it should not get called

            sharing.sendSharingRequests req, res, (err) ->
                err.should.equal "Error"
                done()


    describe 'delete module', ->

        # We declare a phony document that we'll return when needed
        doc = targets: [{url: 'url1.com', preToken: 'preToken1'}]
        # fake request to mimick call `client.del "services/sharing/103"`
        req = params: { id: 103 }

        # stubs of get/remove methods of database
        getStub = (id, callback) -> callback null, doc
        removeStub = (id, callback) -> callback null, true
        dbGetStub    = {}
        dbRemoveStub = {}

        # The use of `(before|after)Each` instead of `(before|after)` might not
        # be efficient but if we want a clean stub before every test...
        beforeEach (done) ->
            dbGetStub    = sinon.stub db, "get", getStub
            dbRemoveStub = sinon.stub db, "remove", removeStub
            done()

        afterEach (done) ->
            dbRemoveStub.restore()
            dbGetStub.restore()
            done()


        it 'should return an error if the document does not exist in the db',
        (done) ->
            dbGetStub.restore() # we want the correct behavior, not the stub
            client.del "services/sharing/103", (err, res, body) ->
                res.statusCode.should.equal 404
                # Funny thing: the message CouchDB sends us to inform us about
                # an error is "stringified" twice hence the following check.
                res.body.should.equal '{"error":"not_found: missing"}'
                done()


        it 'should remove the document from the database', (done) ->
            sharing.delete req, {}, ->
                dbRemoveStub.callCount.should.equal 1
                done()

        it 'should transmit the targets and the shareID to the next callback',
        (done) ->
            sharing.delete req, {}, ->
                should.exist req.share
                should.exist req.share.targets
                should.exist req.share.shareID
                req.share.shareID.should.equal req.params.id
                req.share.targets.should.be.deep.equal doc.targets
                done()


    describe 'stopReplications module', ->

        # Phony document
        doc = targets: [{url: 'url1.com', preToken: 'preToken1'},\
                        {url: 'url2.com', preToken: 'preToken2', repID: 2},
                        {url: 'url3.com', preToken: 'preToken3', repID: 3},
                        {url: 'url4.com', preToken: 'preToken4', repID: 4},
                        {url: 'url5.com', preToken: 'preToken5'}]
        # req to mimick result of preceeding call
        req = share:
            shareID: 103
            targets: doc.targets

        # Stub of Sharing.cancelReplication (lib/sharing.coffee)
        cancelReplicationFn          = (id, callback) -> callback null
        sharingCancelReplicationStub = {}

        before (done) ->
            sharingCancelReplicationStub   = sinon.stub Sharing, \
                "cancelReplication", cancelReplicationFn
            done()

        after (done) ->
            sharingCancelReplicationStub.restore()
            done()

        it 'should cancel the replication for all targets that have a
        replication id', (done) ->
            sharing.stopReplications req, {}, ->
                sharingCancelReplicationStub.callCount.should.equal 3
                done()

        it 'should throw an error if a replication could not be cancelled',
        (done) ->
            sharingCancelReplicationStub.restore() # cancel previous stub
            # create "new" stub that produces an error
            cancelReplicationFn = (id, callback) -> callback "Error"
            sharingCancelReplicationStub = sinon.stub Sharing, \
                "cancelReplication", cancelReplicationFn

            sharing.stopReplications req, {}, (err) ->
                should.exist err
                err.should.equal "Error"
                done()


    describe 'sendDeleteNotifications module', ->

        # Phony document
        targets =
            [{url: 'url1.com', preToken:'preToken1'},
             {url: 'url2.com', preToken:'preToken2', token:'token2', repID: 2},
             {url: 'url3.com', preToken:'preToken3'},
             {url: 'url4.com', preToken:'preToken4', token:'token4', repID: 4},
             {url: 'url5.com', preToken:'preToken5'}]
        urls = (target.url for target in targets)     # extract urls
        tokens = (target.token for target in targets) # extract tokens and pre
        tokens = tokens.concat (target.preToken for target in targets)
        # req to mimick result of preceeding calls
        req = share:
            shareID: 103
            targets: targets

        # sharing.notifyTarget stub (lib/sharing.coffee).
        # Returning `null` mimicks success.
        notifyTargetFn   = (route, notification, callback) -> callback null
        notifyTargetStub = {}

        beforeEach (done) ->
            notifyTargetStub = sinon.stub Sharing, "notifyTarget",
                notifyTargetFn
            done()

        afterEach (done) ->
            notifyTargetStub.restore()
            done()

        it 'should define the notifications correctly and call the route
        "services/sharing/cancel"', (done) ->
            notifyTargetStub.restore() # cancel stub
            # change to a custom stub that tests the values passed
            testNotifyTargetFn = (route, notification, callback) ->
                route.should.equal "services/sharing/cancel"
                urls.should.contain notification.url
                should.exist notification.token
                tokens.should.contain notification.token
                notification.shareID.should.equal req.share.shareID
                notification.desc.should.equal "The sharing
                    #{req.share.shareID} has been deleted"
                callback null

            notifyTargetStub = sinon.stub Sharing, "notifyTarget",
                testNotifyTargetFn

            # mimick Express `res.send`
            resStub =
                status: (_) ->
                    send: (_) ->
                        done()

            # and finally call the test
            sharing.sendDeleteNotifications req, resStub, ->
                done()

        it 'should send notifications to all targets that have a token and a
        repID', (done) ->
            # mimick Express `res.send`
            resStub =
                status: (_) ->
                    send: (_) ->
                        notifyTargetStub.callCount.should.equal targets.length
                        done()

            # and finally call the test
            sharing.sendDeleteNotifications req, resStub, ->
                done()

        it 'should return an error if a notification could not be sent',
        (done) ->
            notifyTargetStub.restore() # cancel stub
            errNotifyTargetFn = (route, notification, callback) ->
                callback "Error"
            notifyTargetStub = sinon.stub Sharing, "notifyTarget",
                errNotifyTargetFn

            sharing.sendDeleteNotifications req, {}, (err) ->
                should.exist err
                err.should.equal "Error"
                done()


    describe 'handleRecipientAnswer module', ->

        # Correct answer structure expected
        answer =
            id: 'IdOfTheRecipientShareDocument'
            shareID: 'IdOfTheSharerShareDocument'
            accepted: true
            preToken: 'preToken'
            url: 'urlOfTheRecipient'
            hostUrl: 'urlOfTheSharer'
            rules: [{id: 1, docType: 'event'}, {id: 2, docType: 'event'}]

        # We stub the addAccess module from lib/token.coffee: we return an
        # error to avoid having our code run entirely if a test fails.
        addAccessFn   = (access, callback) ->
            callback new Error "Error"
        addAccessStub = {}

        # Same for the remove function
        dbRemoveFn = (id, callback) ->
            id.should.equal answer.id
            callback new Error "db.remove"
        dbRemoveStub = {}

        before (done) ->
            addAccessStub = sinon.stub libToken, "addAccess", addAccessFn
            dbRemoveStub = sinon.stub db, "remove", dbRemoveFn
            done()

        after (done) ->
            addAccessStub.restore()
            dbRemoveStub.restore()
            done()


        it 'should return an error if the req structure is incorrect: body is
        empty', (done) ->
            data = {}
            client.post 'services/sharing/sendAnswer/', data,
            (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal "Bad request: body is missing"
                done()

        it 'should return an error if the req structure is incorrect: id is
        missing or empty', (done) ->
            data = _.clone answer
            data.id = undefined
            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal "Bad request: body is incomplete"
                done()

        it 'should return an error if the req structure is incorrect: shareID
        is missing or empty', (done) ->
            data = _.clone answer
            data.shareID = null
            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal "Bad request: body is incomplete"
                done()

        it 'should return an error if the req structure is incorrect: accepted
        is missing or empty', (done) ->
            data = _.clone answer
            data.accepted = ''
            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal "Bad request: body is incomplete"
                done()

        it 'should return an error if the req structure is incorrect: preToken
        is missing or empty', (done) ->
            data = _.clone answer
            data.preToken = ''
            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal "Bad request: body is incomplete"
                done()

        it 'should return an error if the req structure is incorrect: url is
        missing or empty', (done) ->
            data = _.clone answer
            data.url = null
            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal "Bad request: body is incomplete"
                done()

        it 'should return an error if the req structure is incorrect: hostUrl
        is missing or empty', (done) ->
            data = _.clone answer
            data.hostUrl = null
            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal "Bad request: body is incomplete"
                done()

        it 'should return an error if the req structure is incorrect: rules is
        missing or empty', (done) ->
            data = _.clone answer
            data.rules = []
            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal "Bad request: body is incomplete"
                done()

        it 'should return an error if the req structure is incorrect: a rule is
        missing an id', (done) ->
            data = _.clone answer
            data.rules = [{id: 1, docType: 'event'},{id: '', docType: 'event'}]
            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal "Bad request: incorrect rule
                    detected"
                done()

        it 'should return an error if the req structure is incorrect: a rule is
        missing a docType', (done) ->
            data = _.clone answer
            data.rules = [{id: 1, docType: 'event'},{id: 2}]
            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.statusCode.should.equal 400
                res.body.error.should.equal "Bad request: incorrect rule
                    detected"
                done()

        it 'should return an error if addAccess failed', (done) ->
            data = _.clone answer
            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.body.error.should.equal "Error"
                done()

        it 'should remove the sharing document if accepted is false and return
        an error if the document could not be removed', (done) ->
            # set accepted to false
            data = _.clone answer
            data.accepted = false

            # The dbRemoveStub is called during this test, there is a test
            # inside of it that checks that the correct id is passed

            client.post "services/sharing/sendAnswer/", data,
            (err, res, body) ->
                res.body.error.should.equal "db.remove"
                done()

        it 'should call the next callback if req structure is ok: accepted is
        false', (done) ->
            req = body: _.clone answer
            req.body.accepted = false # simulate refusal

            # Cancel previous stub of remove for one that doesn't fail
            dbRemoveStub.restore()
            dbRemoveFnOk = (id, callback) ->
                callback null
            dbRemoveStub = sinon.stub db, "remove", dbRemoveFnOk

            sharing.handleRecipientAnswer req, {}, ->
                should.exist req.share
                req.share.should.deep.equal req.body
                done()

        it 'should call the next callback if req structure is ok: accepted is
        true', (done) ->
            req = body: _.clone answer # copy of correct structure
            addAccessStub.restore() # cancel previous stub
            addAccessFnOk = (access, callback) ->
                callback null # No error is set, addAccess doesn't fail
            addAccessStub = sinon.stub libToken, "addAccess", addAccessFnOk

            sharing.handleRecipientAnswer req, {}, ->
                should.exist req.share
                should.exist req.share.token
                req.share.id.should.equal answer.id
                req.share.shareID.should.equal answer.shareID
                req.share.preToken.should.equal answer.preToken
                req.share.accepted.should.equal answer.accepted
                req.share.url.should.equal answer.url
                req.share.hostUrl.should.equal answer.hostUrl
                req.share.rules.should.deep.equal answer.rules
                done()


    describe 'sendAnswer module', ->

        # Correct answer structure expected
        req = share:
            {
                id: 'IdOfTheRecipientShareDocument'
                shareID: 'IdOfTheSharerShareDocument'
                accepted: true
                preToken: 'preToken'
                url: 'urlOfTheRecipient'
                hostUrl: 'urlOfTheSharer'
                rules: [{id: 1, docType: 'event'}, {id: 2, docType: 'event'}]
                token: 'token'
            }

        # Stub of notifyTarget module: we make it fail for now, we'll redefine
        # the stub once we want it to pass
        notifyTargetFn   = (route, data, callback) ->
            callback new Error "Sharing.notifyTarget"
        notifyTargetStub = {}

        beforeEach (done) ->
            notifyTargetStub = sinon.stub Sharing, "notifyTarget",
                notifyTargetFn
            done()

        afterEach (done) ->
            notifyTargetStub.restore()
            done()


        it 'should return an error if notifyTarget failed', (done) ->
            sharing.sendAnswer req, {}, (err) ->
                err.should.deep.equal new Error "Sharing.notifyTarget"
                done()

        it 'should notify the target', (done) ->
            sharing.sendAnswer req, {}, ->
                notifyTargetStub.callCount.should.equal 1
                done()

        it 'should switch the values of `url` and `hostUrl`', (done) ->
            # We change the stub for one in which we test the values
            # transmitted to the `notifyTarget` module
            notifyTargetStub.restore()
            notifyTargetFnSpy = (route, data, callback) ->
                data.url.should.equal req.share.hostUrl
                data.hostUrl.should.equal req.share.url
                callback new Error "Sharing.notifyTarget"
            notifyTargetStub = sinon.stub Sharing, "notifyTarget",
                notifyTargetFnSpy

            sharing.sendAnswer req, {}, ->
                done() # tests are done in the stub

        it 'should send success if notifyTarget succeeded', (done) ->
            # We change the stub for one that succeeds
            notifyTargetStub.restore()
            notifyTargetFnOk = (route, data, callback) ->
                callback null
            notifyTargetStub = sinon.stub Sharing, "notifyTarget",
                notifyTargetFnOk

            res =
                status: (value) ->
                    value.should.equal 200
                    send: (obj) ->
                        obj.should.deep.equal success: true
                        done()

            sharing.sendAnswer req, res, ->
                done()
