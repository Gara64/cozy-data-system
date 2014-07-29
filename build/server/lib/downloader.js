// Generated by CoffeeScript 1.7.1
var S, fs, http, initLoginCouch;

http = require('http');

fs = require('fs');

S = require('string');

initLoginCouch = function(callback) {
  var data;
  return data = fs.readFile('/etc/cozy/couchdb.login', function(err, data) {
    var lines;
    if (err) {
      return callback(err);
    } else {
      lines = S(data.toString('utf8')).lines();
      return callback(null, lines);
    }
  });
};

module.exports = {
  download: function(id, attachment, callback) {
    var dbName, path;
    dbName = process.env.DB_NAME || 'cozy';
    path = "/" + dbName + "/" + id + "/" + attachment;
    return initLoginCouch(function(err, couchCredentials) {
      var basic, credentialsBuffer, options, pwd;
      if (err && process.NODE_ENV === 'production') {
        return callback(err);
      } else {
        options = {
          host: process.env.COUCH_HOST || 'localhost',
          port: process.env.COUCH_PORT || 5984,
          path: path
        };
        if (!err && process.NODE_ENV === 'production') {
          id = couchCredentials[0];
          pwd = couchCredentials[1];
          credentialsBuffer = new Buffer("" + id + ":" + pwd);
          basic = "Basic " + (credentialsBuffer.toString('base64'));
          options.headers = {
            Authorization: basic
          };
        }
        return http.get(options, function(res) {
          if (res.statusCode === 404) {
            return callback({
              error: 'not_found'
            });
          } else if (res.statusCode !== 200) {
            return callback({
              error: 'error occured while downloading attachment'
            });
          } else {
            return callback(null, res);
          }
        });
      }
    });
  }
};