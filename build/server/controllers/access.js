<<<<<<< HEAD
// Generated by CoffeeScript 1.10.0
var addAccess, client, db, dbHelper, encryption, errors, feed, git, removeAccess, updateAccess;
=======
// Generated by CoffeeScript 1.9.3
var addAccess, db, dbHelper, encryption, errors, feed, git, removeAccess, updateAccess;
>>>>>>> upstream/master

git = require('git-rev');

db = require('../helpers/db_connect_helper').db_connect();

feed = require('../lib/feed');

dbHelper = require('../lib/db_remove_helper');

errors = require('../middlewares/errors');

encryption = require('../lib/encryption');

addAccess = require('../lib/token').addAccess;

updateAccess = require('../lib/token').updateAccess;

removeAccess = require('../lib/token').removeAccess;

module.exports.create = function(req, res, next) {
  var access;
  access = req.body;
  access.id = access.app;
  return addAccess(access, function(err, access) {
    if (err) {
      return next(err);
    } else {
      return res.send(201, access);
    }
  });
};

module.exports.update = function(req, res, next) {
  var access;
  access = req.body;
  return updateAccess(req.params.id, access, function(err, access) {
    if (err) {
      return next(err);
    } else {
      return res.send(200, {
        success: true
      });
    }
  });
};

module.exports.remove = function(req, res, next) {
  return removeAccess(req.doc, function(err) {
    if (err) {
      return next(err);
    } else {
      return res.send(204, {
        success: true
      });
    }
  });
};
