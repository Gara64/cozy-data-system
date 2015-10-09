db = require('../helpers/db_connect_helper').db_connect()
checkPermissions = require('../helpers/utils').checkPermissionsSync
request = require 'request'
url = require 'url'
through = require 'through'

getCredentialsHeader = ->
    username = db.connection.auth.username
    password = db.connection.auth.password
    credentials = "#{username}:#{password}"
    basicCredentials = new Buffer(credentials).toString 'base64'
    return "Basic #{basicCredentials}"


uCaseWord = (word) ->
    switch word
        when 'etag' then return 'ETag'
        else
            return word.replace /^./,(l) ->
                return l.toUpperCase()

uCaseHeader = (headerName) ->
    return headerName.replace /\w*/g, uCaseWord

# Add uppercase for fields headers (removed by nodejs)
couchDBHeaders = (nodeHeaders) ->
    couchHeaders = {}
    for  name in Object.keys(nodeHeaders)
        couchHeaders[uCaseHeader(name)] = nodeHeaders[name]
    return couchHeaders


retrieveJsonDocument = (data) ->
    # Retrieve separator
    startJson = data.indexOf 'Content-Type: application/json'
    if startJson is -1
        # Document is not full
        # Appplication/json isn't is data
        return ['document not full', null]
    json = data.substring 0, startJson
    endSeparator = json.lastIndexOf '\n'
    json = json.substring(0, endSeparator)
    startSeparator = json.lastIndexOf '\n'
    separator = data.substring startSeparator+1, endSeparator-1

    # Retrieve Json part
    startJsonPart = data.indexOf separator
    json = data.substring startJson, data.length
    endJsonPart = json.indexOf(separator)
    if endJsonPart is -1
        # Document is not full
        # JSON part isn't full
        return ['document not full', null]
    jsonPart = json.substring 0, endJsonPart

    # Retrieve JSON document
    startJson = jsonPart.indexOf '{'
    endJson = jsonPart.lastIndexOf '}'
    json = jsonPart.substring startJson, endJson+1
    return [null, JSON.parse(json)]


requestOptions = (req) ->
    # Add his creadentials for CouchDB
    headers = couchDBHeaders(req.headers)
    if process.env.NODE_ENV is "production"
        headers['Authorization'] = getCredentialsHeader()
    else
        # Do not forward 'authorization' header in other environments
        # in order to avoid wrong authentications in CouchDB
        headers['Authorization'] = null

    # Retrieve couchDB url
    targetURL = req.url.replace('replication', db.name)
    host = db.connection.host
    port = db.connection.port
    options =
        method: req.method
        headers: headers
        uri: url.resolve "http://#{host}:#{port}", targetURL

    # Retrieve Json body if necessary
    if req.body and options.headers['Content-Type'] is 'application/json'
        if req.body? and Object.keys(req.body).length > 0
            bodyToTransmit = JSON.stringify req.body
            options['body'] = bodyToTransmit
            # Check doc : bodyToTransmit
            err = checkPermissions req, bodyToTransmit.docType
            return [err, options]
    return [null, options]


module.exports.proxy = (req, res, next) ->
    console.log 'hop'
    [err, options] = requestOptions req
    console.log 'err request: ' + JSON.stringify err
    console.log 'contact couch with options : ' + JSON.stringify options

    # Device isn't authorized if err
    return res.send 403, err if err?

    stream = through()

    couchReq  = request options
        # Receive from couchDB and transmit it to device
        .on 'response', (response) ->
            console.log 'response : ' + JSON.stringify response
            # Set headers and statusCode
            headers = couchDBHeaders(response.headers)
            res.set headers
            res.statusCode = response.statusCode

            # Retrieve body
            data = []
            permissions = false
            response.on 'data', (chunk) ->
                console.log 'data : ' + JSON.stringify chunk
                if req.method is 'GET'
                    if permissions
                        res.write chunk
                    else
                        data.push chunk
                        # Retrieve document
                        if headers['Content-Type'] is 'application/json'
                            try
                                doc = JSON.parse Buffer.concat(data)
                        else
                            content = Buffer.concat(data).toString()
                            [err, doc] = retrieveJsonDocument content
                        # Check document docType
                        if doc
                            err = checkPermissions req, doc.docType
                            console.log 'error? : ' + JSON.stringify err
                            if err
                                # Device isn't authorized
                                res.send 403, err
                                couchReq.end()
                            else
                                permissions = true
                                res.write Buffer.concat(data)
                else
                    res.write chunk

            response.on 'end', ()->
                console.log 'end'
                res.end()

        .on 'error', (err) ->
            console.log 'error : ' + JSON.stringify err
            return res.send 500, err

    stream.pipe couchReq

    # Receive body from device and transmit it on couchDB
    data = []
    permissions = false
    req.on 'data', (chunk) =>
        console.log 'data from supposed device'
        if permissions
            stream.emit 'data', chunk
        else
            data.push chunk
            [err, doc] = retrieveJsonDocument Buffer.concat(data).toString()
            console.log 'err : ' + JSON.stringify err + ' - doc : ' + JSON.stringify doc
            unless err
                # Check doc
                err = checkPermissions req, doc.docType
                if err
                    console.log 'kaboum, not autorized : ' + JSON.stringify err
                    # Device isn't authorized
                    res.send 403, err
                    stream.emit 'end'
                    couchReq.end()
                    req.destroy()
                else
                    permissions = true
                    stream.emit 'data', Buffer.concat(data)

    req.on 'end', () =>
        stream.emit 'end'
