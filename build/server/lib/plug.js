// Generated by CoffeeScript 1.9.0
var BOOT_STATUS, DOCS, IS_INIT, USERS, async, authFP, bootStatus, buildACL, buildSelect, buildSelectDoc, close, deleteDoc, deleteMatch, deleteShare, deleteUser, init, insertDoc, insertDocs, insertShare, insertUser, insertUsers, isInit, java, jdbcJar, match, matchAll, plug, q, selectDocs, selectDocsByDocID, selectUsers, selectUsersByUserID;

java = require('java');

async = require('async');

jdbcJar = './plug/plug_api.jar';

java.classpath.push(jdbcJar);

plug = java.newInstanceSync('org.cozy.plug.Plug');

IS_INIT = false;

BOOT_STATUS = 0;

USERS = 0;

DOCS = 1;

isInit = function() {
  return IS_INIT;
};

bootStatus = function() {
  return BOOT_STATUS;
};

buildSelect = function(table, tuples, callback) {
  var array, res, tuple, _i, _len;
  if (tuples != null) {
    array = [];
    for (_i = 0, _len = tuples.length; _i < _len; _i++) {
      tuple = tuples[_i];
      res = {
        idPlug: tuple[0],
        userID: table === 0 ? tuple[1] : void 0,
        docID: table === 1 ? tuple[1] : void 0,
        shareID: tuple[2],
        userParams: tuple[3]
      };
      array.push(res);
    }
    return callback(res);
  } else {
    return callback(null);
  }
};

buildSelectDoc = function(tuples, callback) {
  var array, res, tuple, _i, _len;
  if (tuples != null) {
    array = [];
    for (_i = 0, _len = tuples.length; _i < _len; _i++) {
      tuple = tuples[_i];
      res = {
        idPlug: tuple[0],
        docID: tuple[1],
        shareID: tuple[2],
        userParams: tuple[3]
      };
      array.push(res);
    }
    return callback(res);
  } else {
    return callback(null);
  }
};

buildACL = function(tuples, shareid, callback) {
  var res, tuple, userInArray, _i, _len;
  console.log('build acl for tuples : ' + JSON.stringify(tuples));
  console.log('shareid : ' + shareid);
  userInArray = function(array, userID) {
    var ar, _i, _len;
    if (array != null) {
      for (_i = 0, _len = array.length; _i < _len; _i++) {
        ar = array[_i];
        if (ar.userID === userID) {
          return true;
        }
      }
    }
    return false;
  };
  if (tuples != null) {
    res = {
      shareID: shareid,
      users: [],
      docIDs: []
    };
    for (_i = 0, _len = tuples.length; _i < _len; _i++) {
      tuple = tuples[_i];
      if (!userInArray(res.users, tuple[0])) {
        res.users.push({
          userID: tuple[0]
        });
      }
      if (!(res.users.length > 1)) {
        res.docIDs.push(tuple[1]);
      }
    }
    return callback(res);
  } else {
    return callback(null);
  }
};

q = async.queue(function(Plug, callback) {
  var p;
  p = Plug.params;
  if (p[0] === 0) {
    return plug.plugInsertDocs(p[1], p[2], p[3], function(err, res) {
      return callback(err, res);
    });
  } else if (p[0] === 1) {
    return plug.plugInsertUsers(p[1], p[2], p[3], function(err, res) {
      return callback(err, res);
    });
  } else if (p[0] === 2) {
    return plug.plugInsertDoc(p[1], p[2], p[3], function(err) {
      return callback(err);
    });
  } else if (p[0] === 3) {
    return plug.plugInsertUser(p[1], p[2], p[3], function(err) {
      return callback(err);
    });
  } else if (p[0] === 4) {
    return plug.plugSelectDocsByDocID(p[1], function(err, tuples) {
      return callback(err, tuples);
    });
  } else if (p[0] === 5) {
    return plug.plugSelectUsersByUserID(p[1], function(err, tuples) {
      return callback(err, tuples);
    });
  } else if (p[0] === 6) {
    return plug.plugMatchAll(p[1], p[2], p[3], function(err, tuples) {
      return callback(err, tuples);
    });
  } else if (p[0] === 7) {
    return plug.plugDeleteMatch(p[1], p[2], p[3], function(err) {
      return callback(err, tuples);
    });
  } else if (p[0] === 8) {
    return plug.plugInit(p[1], function(err, status) {
      return callback(err, status);
    });
  } else if (p[0] === 9) {
    return plug.plugInsertShare(p[1], p[2], function(err) {
      return callback(err);
    });
  } else {
    return callback();
  }
}, 1);

init = function(callback) {

  /*timeoutProtect = setTimeout((->
      timeoutProtect = null
      callback error: 'PlugDB timed out'
  ), 30000)
   */
  var params, port;
  port = '/dev/ttyACM0';
  params = [8, port];
  return q.push({
    params: params
  }, function(err, status) {
    console.log('status : ' + status);
    if (err == null) {
      console.log('PlugDB is ready');
      IS_INIT = true;
      BOOT_STATUS = status;
    }
    return callback(err);
  });
};


/*
    plug.plugInit '/dev/ttyACM0', (err, status) ->
        if timeoutProtect
            clearTimeout timeoutProtect
            if not err?
                console.log 'PlugDB is ready'
                IS_INIT = true
                BOOT_STATUS = status

            callback err
 */

insertDocs = function(docids, shareid, userParams, callback) {
  var array, params;
  array = java.newArray('java.lang.String', docids);
  if (userParams != null) {
    userParams = java.newArray('java.lang.String', userParams);
  }
  params = [0, array, shareid, userParams];
  return q.push({
    params: params
  }, function(err, res) {
    console.log(res + ' docs inserted');
    return callback(err);
  });
};

insertUsers = function(userids, shareid, userParams, callback) {
  var array, params;
  array = java.newArray('java.lang.String', userids);
  if (userParams != null) {
    userParams = java.newArray('java.lang.String', userParams);
  }
  params = [1, array, shareid, userParams];
  return q.push({
    params: params
  }, function(err, res) {
    return callback(err);
  });
};

insertDoc = function(docid, shareid, userParams, callback) {
  var params;
  if (userParams != null) {
    userParams = java.newArray('java.lang.String', userParams);
  }
  params = [2, docid, shareid, userParams];
  return q.push({
    params: params
  }, function(err) {
    return callback(err);
  });
};

insertUser = function(userid, shareid, userParams, callback) {
  var params;
  if (userParams != null) {
    userParams = java.newArray('java.lang.String', userParams);
  }
  params = [3, userid, shareid, userParams];
  return q.push({
    params: params
  }, function(err) {
    return callback(err);
  });
};

insertShare = function(shareid, description, callback) {
  var params;
  params = [9, shareid, description];
  return q.push({
    params: params
  }, function(err) {
    return callback(err);
  });
};

deleteDoc = function(idGlobal, callback) {
  return plug.plugDeleteDoc(parseInt(idGlobal), function(err) {
    return callback(err);
  });
};

deleteUser = function(idGlobal, callback) {
  return plug.plugDeleteUser(parseInt(idGlobal), function(err) {
    return callback(err);
  });
};

deleteShare = function(idGlobal, callback) {
  return plug.plugDeleteShare(parseInt(idGlobal), function(err) {
    return callback(err);
  });
};

selectDocs = function(callback) {
  plug.plugSelectDocs(function(err, results) {
    callback(err, results);
  });
};

selectUsers = function(callback) {
  plug.plugSelectUsers(function(err, results) {
    callback(err, results);
  });
};

selectDocsByDocID = function(docid, callback) {
  var params;
  params = [4, docid];
  return q.push({
    params: params
  }, function(err, tuples) {
    if (err != null) {
      return callback(err);
    }
    return buildSelect(DOCS, tuples, function(result) {
      return callback(null, result);
    });
  });

  /*plug.plugSelectDocsByDocID docid, (err, tuples) ->
      if err? then callback err
      else
          buildSelect DOCS, tuples, (result) ->
              callback null, result
   */
};

selectUsersByUserID = function(userid, callback) {
  var params;
  params = [5, userid];
  return q.push({
    params: params
  }, function(err, tuples) {
    if (err != null) {
      return callback(err);
    }
    return buildSelect(USERS, tuples, function(result) {
      return callback(null, result);
    });
  });

  /*plug.plugSelectUsersByUserID userid, (err, tuples) ->
      if err? then callback err
      else
          buildSelect USERS, tuples, (result) ->
              callback null, result
   */
};

matchAll = function(matchingType, ids, shareid, callback) {
  var array, params;
  array = java.newArray('java.lang.String', ids);
  params = [6, matchingType, array, shareid];
  return q.push({
    params: params
  }, function(err, tuples) {
    if (err != null) {
      console.log('err match : ' + JSON.stringify(err));
    }
    if (err != null) {
      return callback(err);
    }
    return buildACL(tuples, shareid, function(acl) {
      return callback(err, acl);
    });
  });

  /*
  plug.plugMatchAll matchingType, id, shareid, (err, tuples) ->
      buildACL tuples, shareid, (acl) ->
          callback err, acl
   */
};

match = function(matchingType, id, shareid, callback) {
  return plug.plugMatch(matchingType, id, shareid, function(err, result) {
    return callback(err, result);
  });
};

deleteMatch = function(matchingType, idPlug, shareid, callback) {
  var params;
  params = [7, matchingType, idPlug, shareid];
  return q.push({
    params: params
  }, function(err, tuples) {
    if (err != null) {
      return callback(err);
    }
    return buildACL(tuples, shareid, function(acl) {
      return callback(err, acl);
    });
  });

  /*
  idPlug = parseInt(idPlug) # Necessary for java
  plug.plugDeleteMatch matchingType, idPlug, shareid, (err, tuples) ->
      buildACL tuples, shareid, (acl) ->
          callback err, acl
   */
};

close = function(callback) {
  console.log('go close');
  return plug.plugClose(function(err) {
    if (err) {
      return callback(err);
    } else {
      IS_INIT = false;
      return callback(null);
    }
  });
};

authFP = function(callback) {
  plug.plugFPAuthentication(function(err, authID) {
    callback(err, authID);
  });
};

exports.USERS = USERS;

exports.DOCS = DOCS;

exports.isInit = isInit;

exports.bootStatus = bootStatus;

exports.init = init;

exports.insertDocs = insertDocs;

exports.insertDoc = insertDoc;

exports.insertUsers = insertUsers;

exports.insertUser = insertUser;

exports.insertShare = insertShare;

exports.deleteDoc = deleteDoc;

exports.deleteUser = deleteUser;

exports.deleteShare = deleteShare;

exports.selectDocs = selectDocs;

exports.selectUsers = selectUsers;

exports.selectDocsByDocID = selectDocsByDocID;

exports.selectUsersByUserID = selectUsersByUserID;

exports.matchAll = matchAll;

exports.match = match;

exports.deleteMatch = deleteMatch;

exports.close = close;

exports.authFP = authFP;
