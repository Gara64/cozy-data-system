// Generated by CoffeeScript 1.10.0
var addAccess, checkToken, db, docIDs, fs, initAccess, initHomeProxy, log, permissions, productionOrTest, ref, tokens, updatePermissions,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

db = require('../helpers/db_connect_helper').db_connect();

fs = require('fs');

log = require('printit')({
  prefix: 'token'
});

permissions = {};

tokens = {};

docIDs = {};

productionOrTest = (ref = process.env.NODE_ENV) === 'production' || ref === 'test';

checkToken = module.exports.checkToken = function(auth) {
  var password, username;
  if (auth !== "undefined" && (auth != null)) {
    auth = auth.substr(5, auth.length - 1);
    auth = new Buffer(auth, 'base64').toString('ascii');
    username = auth.split(':')[0];
    password = auth.split(':')[1];
    if (password !== void 0 && tokens[username] === password) {
      return [null, true, username];
    } else {
      return [null, false, username];
    }
  } else {
    return [null, false, null];
  }
};

module.exports.checkDocType = function(auth, docType, id, callback) {
  var err, isAuthenticated, name, ref1, ref2;
  if (productionOrTest) {
    ref1 = checkToken(auth), err = ref1[0], isAuthenticated = ref1[1], name = ref1[2];
    if (isAuthenticated) {
      if (docType != null) {
        docType = docType.toLowerCase();
        if (permissions[name][docType] != null) {
          if (permissions[name][docType].sharing === true) {
            console.log('sharing check : ' + docIDs[name] + ' id : ' + id);
            return callback(null, name, indexOf.call(docIDs[name], id) >= 0);
          } else {
            return callback(null, name, true);
          }
        } else if (permissions[name]["all"] != null) {
          return callback(null, name, true);
        } else {
          return callback(null, name, false);
        }
      } else {
        return callback(null, name, true);
      }
    } else {
      return callback(null, false, false);
    }
  } else {
    ref2 = checkToken(auth), err = ref2[0], isAuthenticated = ref2[1], name = ref2[2];
    if (name == null) {
      name = 'unknown';
    }
    return callback(null, name, true);
  }
};

module.exports.checkDocTypeSync = function(auth, docType, id) {
  var err, isAuthenticated, name, ref1, ref2;
  if (productionOrTest) {
    ref1 = checkToken(auth), err = ref1[0], isAuthenticated = ref1[1], name = ref1[2];
    if (isAuthenticated) {
      if (docType != null) {
        docType = docType.toLowerCase();
        if (permissions[name][docType] != null) {
          if (permissions[name][docType].sharing === true) {
            console.log('sharing check : ' + docIDs[name] + ' id : ' + id);
            return callback(null, name, indexOf.call(docIDs[name], id) >= 0);
          } else {
            return callback(null, name, true);
          }
        } else if (permissions[name]["all"] != null) {
          return [null, name, true];
        } else {
          return [null, name, false];
        }
      } else {
        return [null, name, true];
      }
    } else {
      return [null, false, false];
    }
  } else {
    ref2 = checkToken(auth), err = ref2[0], isAuthenticated = ref2[1], name = ref2[2];
    if (name == null) {
      name = 'unknown';
    }
    return [null, name, true];
  }
};

module.exports.checkProxyHome = function(auth, callback) {
  var password, username;
  if (productionOrTest) {
    if (auth !== "undefined" && (auth != null)) {
      auth = auth.substr(5, auth.length - 1);
      auth = new Buffer(auth, 'base64').toString('ascii');
      username = auth.split(':')[0];
      password = auth.split(':')[1];
      if (password !== void 0 && tokens[username] === password) {
        if (username === "proxy" || username === "home") {
          return callback(null, true);
        } else {
          return callback(null, false);
        }
      } else {
        return callback(null, false);
      }
    } else {
      return callback(null, false);
    }
  } else {
    return callback(null, true);
  }
};

updatePermissions = function(access, callback) {
  var description, docType, login, ref1;
  login = access.login;
  if (productionOrTest) {
    if (access.token != null) {
      tokens[login] = access.token;
    }
    permissions[login] = {};
    if (access.permissions != null) {
      ref1 = access.permissions;
      for (docType in ref1) {
        description = ref1[docType];
        permissions[login][docType.toLowerCase()] = description;
      }
    }
    if (access.docIDs != null) {
      docIDs[login] = access.docIDs;
    }
    if (callback != null) {
      return callback();
    }
  } else {
    if (callback != null) {
      return callback();
    }
  }
};

addAccess = module.exports.addAccess = function(doc, callback) {
  var access;
  access = {
    docType: "Access",
    login: doc.slug || doc.login,
    token: doc.password,
    app: doc.id || doc._id,
    permissions: doc.permissions,
    docIDs: doc.docIDs
  };
  return db.save(access, function(err, doc) {
    if (err != null) {
      log.error(err);
    }
    return updatePermissions(access, function() {
      if (callback != null) {
        return callback(null, access);
      }
    });
  });
};

module.exports.updateAccess = function(id, doc, callback) {
  return db.view('access/byApp', {
    key: id
  }, function(err, accesses) {
    var access;
    if (accesses.length > 0) {
      access = accesses[0].value;
      delete permissions[access.login];
      delete tokens[access.login];
      access.login = doc.slug || access.login;
      access.token = doc.password || access.token;
      access.permissions = doc.permissions || access.permissions;
      return db.save(access._id, access, function(err, body) {
        if (err != null) {
          log.error(err);
        }
        return updatePermissions(access, function() {
          if (callback != null) {
            return callback(null, access);
          }
        });
      });
    } else {
      return addAccess(doc, callback);
    }
  });
};

module.exports.removeAccess = function(doc, callback) {
  return db.view('access/byApp', {
    key: doc._id
  }, function(err, accesses) {
    var access;
    if ((err != null) && (callback != null)) {
      return callback(err);
    }
    if (accesses.length > 0) {
      access = accesses[0].value;
      delete permissions[access.login];
      delete tokens[access.login];
      return db.remove(access._id, access._rev, function(err) {
        if (callback != null) {
          return callback(err);
        }
      });
    } else {
      if (callback != null) {
        return callback();
      }
    }
  });
};

initHomeProxy = function(callback) {
  var token;
  token = process.env.TOKEN;
  token = token.split('\n')[0];
  tokens['home'] = token;
  permissions.home = {
    "application": "authorized",
    "access": "authorized",
    "notification": "authorized",
    "photo": "authorized",
    "file": "authorized",
    "background": "authorized",
    "folder": "authorized",
    "contact": "authorized",
    "album": "authorized",
    "message": "authorized",
    "binary": "authorized",
    "user": "authorized",
    "device": "authorized",
    "alarm": "authorized",
    "event": "authorized",
    "userpreference": "authorized",
    "cozyinstance": "authorized",
    "encryptedkeys": "authorized",
    "stackapplication": "authorized",
    "send mail to user": "authorized",
    "send mail from user": "authorized",
    "usersharing": "authorized"
  };
  tokens['proxy'] = token;
  permissions.proxy = {
    "access": "authorized",
    "application": "authorized",
    "user": "authorized",
    "cozyinstance": "authorized",
    "device": "authorized",
    "usetracker": "authorized",
    "send mail to user": "authorized",
    "usersharing": "authorized"
  };
  return callback(null);
};

initAccess = function(access, callback) {
  var description, docType, name, ref1;
  name = access.login;
  tokens[name] = access.token;
  if ((access.permissions != null) && access.permissions !== null) {
    permissions[name] = {};
    ref1 = access.permissions;
    for (docType in ref1) {
      description = ref1[docType];
      docType = docType.toLowerCase();
      permissions[name][docType] = description;
    }
  }
  if (access.docIDs != null) {
    docIDs[name] = access.docIDs;
  }
  return callback(null);
};

module.exports.init = function(callback) {
  if (productionOrTest) {
    return initHomeProxy(function() {
      return db.view('access/all', function(err, accesses) {
        if (err != null) {
          return callback(new Error("Error in view"));
        }
        accesses.forEach(function(access) {
          return initAccess(access, function() {});
        });
        return callback(tokens, permissions);
      });
    });
  } else {
    return callback(tokens, permissions);
  }
};
