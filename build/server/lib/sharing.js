// Generated by CoffeeScript 1.10.0
var async, binaryHandling, bufferIds, cancelReplication, convertTuples, db, dbHost, dbPort, dbUrl, getActiveTasks, getCozyAddressFromUserID, getRuleById, getUserInfo, getbinariesIds, mapDoc, mapDocInRules, matchAfterInsert, removeDuplicates, removeNullValues, removeReplication, request, request2, rules, saveReplication, saveRule, shareDocs, shareIDInArray, sharingProcess, startShares, updateActiveRep, userInArray, userSharing;

db = require('../helpers/db_connect_helper').db_connect();

async = require('async');

request = require('request-json');

request2 = require('request');

rules = [];

bufferIds = [];

dbHost = db.connection.host;

dbPort = db.connection.port;

dbUrl = "http://" + dbHost + ":" + dbPort;

module.exports.getDomain = function(callback) {
  return db.view('cozyinstance/all', function(err, instance) {
    var domain, ref;
    if (err != null) {
      return callback(err);
    }
    if ((instance != null ? (ref = instance[0]) != null ? ref.value.domain : void 0 : void 0) != null) {
      domain = instance[0].value.domain;
      if (!domain.indexOf('http' > -1)) {
        console.log('domain : ' + domain);
        domain = "https://" + domain + "/";
      }
      return callback(null, domain);
    } else {
      return callback(null);
    }
  });
};

module.exports.evalInsert = function(doc, id, callback) {
  console.log('doc insert : ' + JSON.stringify(doc));
  if (doc.docType === 'sharingrule') {
    return createRule(doc, id, function(err) {
      return callback(err);
    });
  } else {
    return mapDocInRules(doc, id, function(err, mapResults) {
      if (err != null) {
        return callback(err);
      }

      /*
      async.eachSeries mapResults, insertResults, (err) ->
          return callback err if err?
      
          console.log 'mapping results insert : ' + JSON.stringify mapResults
          matchAfterInsert mapResults, (err, acls) ->
              #acl :
              #console.log 'acls : ' + JSON.stringify acls
      
              return callback err if err?
              return callback null unless acls? and acls.length > 0
      
      
              startShares acls, (err) ->
                  callback err
       */
    });
  }
};

module.exports.evalUpdate = function(id, isBinaryUpdate, callback) {
  return db.get(id, function(err, doc) {
    console.log('doc update : ' + JSON.stringify(doc));
    return mapDocInRules(doc, id, function(err, mapResults) {
      if (err != null) {
        return callback(err);
      }
      return console.log('mapping results update : ' + JSON.stringify(mapResults));

      /*
      selectInPlug id, (err, selectResults) ->
          return callback err if err?
      
          updateProcess id, mapResults, selectResults, isBinaryUpdate, (err, res) ->
              callback err, res
       */
    });
  });
};

mapDocInRules = function(doc, id, callback) {
  var evalRule;
  evalRule = function(rule, _callback) {
    var filterDoc, filterUser, mapResult, saveResult;
    mapResult = {};
    saveResult = function(id, shareID, userParams, binaries, isDoc) {
      var res;
      res = {};
      if (isDoc) {
        res.docID = id;
      } else {
        res.userID = id;
      }
      res.shareID = shareID;
      res.userParams = userParams;
      res.binaries = binaries;
      if (isDoc) {
        return mapResult.doc = res;
      } else {
        return mapResult.user = res;
      }
    };
    filterDoc = rule.filterDoc;
    filterUser = rule.filterUser;
    return mapDoc(doc, id, rule.id, filterDoc, function(isDocMaped) {
      var binIds;
      if (isDocMaped) {
        console.log('doc maped !! ');
        binIds = getbinariesIds(doc);
        saveResult(id, rule.id, filterDoc.userParam, binIds, true);
      }
      return mapDoc(doc, id, rule.id, filterUser, function(isUserMaped) {
        if (isUserMaped) {
          console.log('user maped !! ');
          binIds = getbinariesIds(doc);
          saveResult(id, rule.id, filterUser.userParam, binIds, false);
        }
        if ((mapResult.doc == null) && (mapResult.user == null)) {
          return _callback(null, null);
        } else {
          return _callback(null, mapResult);
        }
      });
    });
  };
  return async.map(rules, evalRule, function(err, mapResults) {
    mapResults = Array.prototype.slice.call(mapResults);
    removeNullValues(mapResults);
    return callback(err, mapResults);
  });
};

mapDoc = function(doc, docID, shareID, filter, callback) {
  var ret;
  if (eval(filter.rule)) {
    if (filter.userDesc) {
      ret = eval(filer.userDesc);
    } else {
      ret = true;
    }
    return callback(ret);
  } else {
    return callback(false);
  }
};

matchAfterInsert = function(mapResults, callback) {
  if ((mapResults != null) && mapResults.length > 0) {
    return async.mapSeries(mapResults, matching, function(err, acls) {
      return callback(err, acls);
    });
  } else {
    return callback(null);
  }
};


/*
 * Send the match command to PlugDB
matching = (mapResult, callback) ->


    async.series [
        (_callback) ->
            return _callback null unless mapResult.doc?
            doc = mapResult.doc
            matchType = plug.USERS
            ids = if doc.binaries? then doc.binaries else [doc.docID]

            plug.matchAll matchType, ids, doc.shareID, (err, acl) ->
                _callback err, acl
        ,
        (_callback) ->
            return _callback null unless mapResult.user?
            user = mapResult.user
            matchType = plug.DOCS
            ids = if user.binaries? then user.binaries else [user.userID]

            plug.matchAll matchType, ids, user.shareID, (err, acl) ->
                _callback err, acl

    ],
    (err, results) ->
        acls = {doc: results[0], user: results[1]}
        callback err, acls

    #if acl?
     * Add the shareID at the beginning
     * acl = Array.prototype.slice.call( acl )
     * acl.unshift mapResult.shareID
 */

startShares = function(acls, callback) {
  if (!((acls != null) && acls.length > 0)) {
    return callback(null);
  }
  return async.each(acls, function(acl, _callback) {
    return async.parallel([
      function(_cb) {
        if (acl.doc == null) {
          return _cb(null);
        }
        return sharingProcess(acl.doc, function(err) {
          return _cb(err);
        });
      }, function(_cb) {
        if (acl.user == null) {
          return _cb(null);
        }
        return sharingProcess(acl.user, function(err) {
          return _cb(err);
        });
      }
    ], function(err) {
      return _callback(err);
    });
  }, function(err) {
    return callback(err);
  });
};

sharingProcess = function(share, callback) {
  if (!((share != null) && (share.users != null))) {
    return callback(null);
  }
  return async.each(share.users, function(user, _callback) {
    return getCozyAddressFromUserID(user.userID, function(err, url) {
      user.url = "http://192.168.50.6:9104";
      return userSharing(share.shareID, user, share.docIDs, function(err) {
        return _callback(err);
      });
    });
  }, function(err) {
    return callback(err);
  });
};

userSharing = function(shareID, user, ids, callback) {
  var pwd, ref, replicationID, rule;
  console.log('share with user : ' + JSON.stringify(user));
  rule = getRuleById(shareID);
  if (rule == null) {
    return callback(null);
  }
  ref = getUserInfo(rule.activeReplications, user.userID), replicationID = ref[0], pwd = ref[1];
  user.pwd = pwd;
  console.log('replication id : ' + replicationID + ' - pwd : ' + user.pwd);
  if (replicationID != null) {
    return cancelReplication(replicationID, function(err) {
      if (err != null) {
        return callback(err);
      }
      return shareDocs(user, ids, rule, function(err) {
        return callback(err);
      });
    });
  } else {
    bufferIds = ids;
    return notifyTarget(user, rule, function(err) {
      return callback(err);
    });
  }
};

shareDocs = function(user, ids, rule, callback) {
  return replicateDocs(user, ids, function(err, repID) {
    if (err != null) {
      return callback(err);
    }
    return saveReplication(rule, user.userID, repID, user.pwd, function(err) {
      return callback(err, repID);
    });
  });
};

module.exports.notifyTarget = function(targetURL, params, callback) {
  var remote;
  remote = request.newClient(targetURL);
  return remote.post("sharing/request", params, function(err, result, body) {
    console.log('body : ' + JSON.stringify(body));
    return callback(err, result, body);
  });
};

module.exports.answerHost = function(hostURL, answer, callback) {
  var remote;
  remote = request.newClient(hostURL);
  return remote.post("sharing/answer", answer, function(err, result, body) {
    console.log('body : ' + JSON.stringify(body));
    return callback(err, result, body);
  });
};

module.exports.targetAnswer = function(req, res, next) {
  var answer;
  console.log('answer : ' + JSON.stringify(req.body.answer));
  answer = req.body.answer;
  if (answer.accepted === true) {
    console.log('target is ok for sharing, lets go');
    return next();

    /*
    rule = getRuleById answer.shareID
    user =
        userID: answer.userID
        url: "http://192.168.50.6:9104"
        pwd: answer.password
    shareDocs user, bufferIds, rule, (err, repID) ->
        return next err if err?
        res.send 500 unless repID?
        res.send 200, repID
        else
    bufferIds = []
    console.log 'target is not ok for sharing, drop it'
     */
  } else {
    return res.send(200, {
      success: true
    });
  }
};

module.exports.replicateDocs = function(params, callback) {
  var err, headers, options, repSourceToTarget;
  console.log('params : ' + JSON.stringify(params));
  if (!((params.url != null) && (params.pwd != null) && (params.docIDs != null))) {
    err = new Error('Parameters missing');
    err.status = 400;
    callback(err);
  }
  repSourceToTarget = {
    source: "cozy",
    target: params.url + "/replication",
    continuous: params.sync || false,
    doc_ids: params.docIDs
  };

  /*repTargetToSource =
      source: "cozy"
      target: sourceURL
      continuous: true
      doc_ids: ids
   */
  console.log('rep data : ' + JSON.stringify(repSourceToTarget));
  headers = {
    'Content-Type': 'application/json'
  };
  options = {
    method: 'POST',
    headers: headers,
    uri: dbUrl + "/_replicate"
  };
  options['body'] = JSON.stringify(repSourceToTarget);
  return request2(options, function(err, res, body) {
    var repID;
    if (err != null) {
      return callback(err);
    } else if (!body.ok) {
      console.log(JSON.stringify(body));
      return callback(null, body);
    } else {
      console.log('Replication from source succeeded \o/');
      repID = body._local_id;
      return callback(null, repID);
    }
  });
};

updateActiveRep = function(shareID, activeReplications, callback) {
  return db.get(shareID, function(err, doc) {
    if (err != null) {
      return callback(err);
    }
    doc.activeReplications = activeReplications;
    console.log('active rep : ' + JSON.stringify(activeReplications));
    return db.save(shareID, doc, function(err, res) {
      return callback(err);
    });
  });
};

saveReplication = function(rule, userID, replicationID, pwd, callback) {
  var isUpdate, ref;
  if (!((rule != null) && (replicationID != null))) {
    return callback(null);
  }
  console.log('save replication ' + replicationID + ' with userid ' + userID);
  console.log('pwd : ' + pwd);
  if (((ref = rule.activeReplications) != null ? ref.length : void 0) > 0) {
    isUpdate = false;
    return async.each(rule.activeReplications, function(rep, _callback) {
      if ((rep != null ? rep.userID : void 0) === userID) {
        rep.replicationID = replicationID;
        isUpdate = true;
      }
      return _callback(null);
    }, function(err) {
      console.log('is update : ' + isUpdate);
      if (!isUpdate) {
        rule.activeReplications.push({
          userID: userID,
          replicationID: replicationID,
          pwd: pwd
        });
      }
      return updateActiveRep(rule.id, rule.activeReplications, function(err) {
        return callback(err);
      });
    });
  } else {
    rule.activeReplications = [
      {
        userID: userID,
        replicationID: replicationID,
        pwd: pwd
      }
    ];
    return updateActiveRep(rule.id, rule.activeReplications, function(err) {
      return callback(err);
    });
  }
};

removeReplication = function(rule, replicationID, userID, callback) {
  if (!((rule != null) && (replicationID != null))) {
    return callback(null);
  }
  return cancelReplication(replicationID, function(err) {
    if (err != null) {
      return callback(err);
    }
    if (rule.activeReplications != null) {
      return async.each(rule.activeReplications, function(rep, _callback) {
        var i;
        if ((rep != null ? rep.userID : void 0) === userID) {
          i = rule.activeReplications.indexOf(rep);
          if (i > -1) {
            rule.activeReplications.splice(i, 1);
          }
          return updateActiveRep(rule.id, rule.activeReplications, function(err) {
            return _callback(err);
          });
        } else {
          return _callback(null);
        }
      }, function(err) {
        return callback(err);
      });
    } else {
      return updateActiveRep(rule.id, [], function(err) {
        return callback(err);
      });
    }
  });
};

cancelReplication = function(replicationID, callback) {
  var args, couchClient;
  couchClient = request.newClient("http://localhost:5984");
  args = {
    replication_id: replicationID,
    cancel: true
  };
  console.log('cancel args ' + JSON.stringify(args));
  return couchClient.post("_replicate", args, function(err, res, body) {
    if (err != null) {
      return callback(err);
    } else {
      console.log('Cancel replication');
      console.log(JSON.stringify(body));
      return callback();
    }
  });
};

getCozyAddressFromUserID = function(userID, callback) {
  if (userID != null) {
    return db.get(userID, function(err, user) {
      if (user != null) {
        console.log('user url : ' + user.url);
      }
      if (err != null) {
        return callback(err);
      } else {
        return callback(null, user.url);
      }
    });
  } else {
    return callback(null);
  }
};

getbinariesIds = function(doc) {
  var bin, ids, val;
  if (doc.binary != null) {
    ids = (function() {
      var ref, results;
      ref = doc.binary;
      results = [];
      for (bin in ref) {
        val = ref[bin];
        results.push(val.id);
      }
      return results;
    })();
    return ids;
  }
};

binaryHandling = function(mapRes, callback) {
  if ((mapRes.doc.binaries != null) || (mapRes.user.binaries != null)) {
    console.log('go insert binaries');
    return insertResults(mapRes, function(err) {
      if (err != null) {
        return callback(err);
      }
      return matching(mapRes, function(err, acls) {
        if (err != null) {
          return callback(err);
        }
        if (acls == null) {
          return callback(null);
        }
        return startShares([acls], function(err) {
          return callback(err);
        });
      });
    });
  } else {
    console.log('no binary in the doc');
    return callback(null);
  }
};

getActiveTasks = function(client, callback) {
  return client.get("_active_tasks", function(err, res, body) {
    var j, len, repIds, task;
    if ((err != null) || (body.length == null)) {
      return callback(err);
    } else {
      for (j = 0, len = body.length; j < len; j++) {
        task = body[j];
        if (task.replication_id) {
          repIds = task.replication_id;
        }
      }
      return callback(null, repIds);
    }
  });
};


/*
 * Particular case at the doc evaluation where a new rule is inserted
createRule = (doc, id, callback) ->
    plug.insertShare id, doc.name, (err) ->
        if err?
            callback err
        else
            rule =
                id: id
                name: doc.name
                filterDoc: doc.filterDoc
                filterUser: doc.filterUser
            saveRule rule
            console.log 'rule inserted'
            callback null

module.exports.deleteRule = (doc, callback) ->
module.exports.updateRule = (doc, callback) ->
 */

saveRule = function(rule, callback) {
  var activeReplications, filterDoc, filterUser, id, name;
  id = rule._id;
  name = rule.name;
  filterDoc = rule.filterDoc;
  filterUser = rule.filterUser;
  if (rule.activeReplications) {
    activeReplications = rule.activeReplications;
  }
  return rules.push({
    id: id,
    name: name,
    filterDoc: filterDoc,
    filterUser: filterUser,
    activeReplications: activeReplications
  });
};

module.exports.initRules = function(callback) {
  return db.view('sharingRule/all', function(err, rules) {
    if (err != null) {
      return callback(new Error("Error in view"));
    }
    rules.forEach(function(rule) {
      return saveRule(rule);
    });
    return callback();
  });
};

userInArray = function(array, userID) {
  var ar, j, len;
  if (array != null) {
    for (j = 0, len = array.length; j < len; j++) {
      ar = array[j];
      if (ar.userID === userID) {
        return true;
      }
    }
  }
  return false;
};

getUserInfo = function(array, userID) {
  var activeRep, j, len;
  if (array != null) {
    for (j = 0, len = array.length; j < len; j++) {
      activeRep = array[j];
      if (activeRep.userID === userID) {
        return [activeRep.replicationID, activeRep.pwd];
      }
    }
  }
  return [null, null];
};

shareIDInArray = function(array, shareID) {
  var ar, j, len;
  if (array != null) {
    for (j = 0, len = array.length; j < len; j++) {
      ar = array[j];
      if (((ar != null ? ar.doc : void 0) != null) && ar.doc.shareID === shareID) {
        return ar;
      }
      if (((ar != null ? ar.user : void 0) != null) && ar.user.shareID === shareID) {
        return ar;
      }
    }
  }
  return null;
};

getRuleById = function(shareID, callback) {
  var j, len, rule;
  for (j = 0, len = rules.length; j < len; j++) {
    rule = rules[j];
    if (rule.id === shareID) {
      return rule;
    }
  }
};

removeNullValues = function(array) {
  var i, j, ref, results;
  if (array != null) {
    results = [];
    for (i = j = ref = array.length - 1; ref <= 0 ? j <= 0 : j >= 0; i = ref <= 0 ? ++j : --j) {
      if (array[i] === null) {
        results.push(array.splice(i, 1));
      } else {
        results.push(void 0);
      }
    }
    return results;
  }
};

removeDuplicates = function(array) {
  var j, key, ref, res, results, value;
  if (array.length === 0) {
    return [];
  }
  res = {};
  for (key = j = 0, ref = array.length - 1; 0 <= ref ? j <= ref : j >= ref; key = 0 <= ref ? ++j : --j) {
    res[array[key]] = array[key];
  }
  results = [];
  for (key in res) {
    value = res[key];
    results.push(value);
  }
  return results;
};

convertTuples = function(tuples, callback) {
  var array, j, len, res, tuple;
  if (tuples != null) {
    array = [];
    for (j = 0, len = tuples.length; j < len; j++) {
      tuple = tuples[j];
      res = {
        shareID: tuple[2],
        userParams: tuple[3]
      };
      array.push(res);
    }
    return array;
  }
};
