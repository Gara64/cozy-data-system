// Generated by CoffeeScript 1.7.1
var S, cradle, db, fs, initLoginCouch, setup_credentials;

cradle = require('cradle');

S = require('string');

fs = require('fs');

initLoginCouch = function() {
  var data, err, lines;
  try {
    data = fs.readFileSync('/etc/cozy/couchdb.login');
  } catch (_error) {
    err = _error;
    console.log("No CouchDB credentials file found: /etc/cozy/couchdb.login");
    process.exit(1);
  }
  lines = S(data.toString('utf8')).lines();
  return lines;
};

setup_credentials = function() {
  var credentials, loginCouch;
  credentials = {
    host: 'localhost',
    port: '5984',
    cache: false,
    raw: false,
    db: 'cozy'
  };
  if (process.env.NODE_ENV === 'production') {
    loginCouch = initLoginCouch();
    credentials.auth = {
      username: loginCouch[0],
      password: loginCouch[1]
    };
  }
  return credentials;
};

db = null;

exports.db_connect = function() {
  var connection, credentials;
  if (db == null) {
    credentials = setup_credentials();
    connection = new cradle.Connection(credentials);
    db = connection.database(credentials.db);
  }
  return db;
};
