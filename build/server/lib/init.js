// Generated by CoffeeScript 1.10.0
var async, db, defaultPermissions, getLostBinaries, initTokens, log, permissionsManager, sharing, thumb;

log = require('printit')({
  date: true,
  prefix: 'lib/init'
});

db = require('../helpers/db_connect_helper').db_connect();

async = require('async');

permissionsManager = require('./token');

thumb = require('./thumb');

initTokens = require('./token').init;

sharing = require('./sharing');

defaultPermissions = {
  'File': {
    'description': 'Usefull to synchronize your files'
  },
  'Folder': {
    'description': 'Usefull to synchronize your folder'
  },
  'Notification': {
    'description': 'Usefull to synchronize your notification'
  },
  'Binary': {
    'description': 'Usefull to synchronize your files'
  }
};

getLostBinaries = exports.getLostBinaries = function(callback) {
  var lostBinaries;
  lostBinaries = [];
  return db.view('binary/all', function(err, binaries) {
    if (!err && binaries.length > 0) {
      return db.view('binary/byDoc', function(err, docs) {
        var binary, doc, i, j, keys, len, len1;
        if (!err && (docs != null)) {
          keys = [];
          for (i = 0, len = docs.length; i < len; i++) {
            doc = docs[i];
            keys[doc.key] = true;
          }
          for (j = 0, len1 = binaries.length; j < len1; j++) {
            binary = binaries[j];
            if (keys[binary.id] == null) {
              lostBinaries.push(binary.id);
            }
          }
          return callback(null, lostBinaries);
        } else {
          return callback(null, []);
        }
      });
    } else {
      return callback(err, []);
    }
  });
};

exports.removeLostBinaries = function(callback) {
  return getLostBinaries(function(err, binaries) {
    if (err != null) {
      return callback(err);
    }
    return async.forEachSeries(binaries, function(binary, cb) {
      log.info("Remove binary " + binary);
      return db.get(binary, function(err, doc) {
        if (!err && doc) {
          return db.remove(doc._id, doc._rev, function(err, doc) {
            if (err) {
              log.error(err);
            }
            return cb();
          });
        } else {
          if (err) {
            log.error(err);
          }
          return cb();
        }
      });
    }, callback);
  });
};

exports.addAccesses = function(callback) {
  var addAccess;
  addAccess = function(docType, cb) {
    return db.view(docType + "/all", function(err, apps) {
      if ((err != null) || apps.length === 0) {
        return cb(err);
      }
      return async.forEachSeries(apps, function(app, cb) {
        app = app.value;
        return db.view('access/byApp', {
          key: app._id
        }, function(err, accesses) {
          if ((err != null) || accesses.length > 0) {
            return cb(err);
          }
          if ((accesses != null ? accesses.length : void 0) === 0) {
            if (docType === "device") {
              app.permissions = defaultPermissions;
            }
            return permissionsManager.addAccess(app, function(err, access) {
              delete app.password;
              delete app.token;
              delete app.permissions;
              return db.save(app, function(err, doc) {
                if (err != null) {
                  log.error(err);
                }
                return cb();
              });
            });
          } else {
            return cb();
          }
        });
      }, cb);
    });
  };
  return addAccess('application', function(err) {
    if (err != null) {
      log.error(err);
    }
    return addAccess('device', function(err) {
      if (err != null) {
        log.error(err);
      }
      return initTokens(function(tokens, permissions) {
        return typeof callback === "function" ? callback() : void 0;
      });
    });
  });
};

exports.addThumbs = function(callback) {
  return db.view('file/withoutThumb', function(err, files) {
    if (err) {
      return callback(err);
    } else if (files.length === 0) {
      return callback();
    } else {
      return async.forEach(files, function(file, cb) {
        thumb.create(file.id, false);
        return cb();
      }, callback);
    }
  });
};

exports.removeDocWithoutDocType = function(callback) {
  return db.view('withoutDocType/all', function(err, docs) {
    if (err) {
      return callback(err);
    } else if (docs.length === 0) {
      return callback();
    } else {
      return async.forEachSeries(docs, function(doc, cb) {
        return db.remove(doc.value._id, doc.value._rev, function(err, doc) {
          if (err) {
            log.error(err);
          }
          return cb();
        });
      }, callback);
    }
  });
};

exports.addSharingRules = function(callback) {
  return sharing.initRules(function(err) {
    if (err) {
      return callback(err);
    } else {
      return callback();
    }
  });
};
