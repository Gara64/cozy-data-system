var async, cancelReplication, convertTuples, db, deleteResults, getActiveTasks, getCozyAddressFromUserID, getRepID, getRuleById, insertResults, mapDoc, mapDocInRules, matchAfterInsert, matching, plug, removeDuplicates, removeNullValues, removeReplication, replicateDocs, request, rules, saveReplication, saveRule, selectInPlug, shareDocs, shareIDInArray, sharingProcess, startShares, updateActiveRep, updateProcess, updateResults, userInArray, userSharing;

plug = require('./plug');

db = require('../helpers/db_connect_helper').db_connect();

async = require('async');

request = require('request-json');

rules = [];

module.exports.evalInsert = function(doc, id, callback) {
  return mapDocInRules(doc, id, function(err, mapResults) {
    if (err != null) {
      return callback(err);
    } else {
      return async.eachSeries(mapResults, insertResults, function(err) {
        if (err != null) {
          return callback(err);
        } else {
          console.log('mapping results : ' + JSON.stringify(mapResults));
          return matchAfterInsert(mapResults, function(err, acls) {
            if (err != null) {
              return callback(err);
            } else if ((acls != null) && acls.length > 0) {
              return startShares(acls, function(err) {
                return callback(err);
              });
            } else {
              return callback(null);
            }
          });
        }
      });
    }
  });
};

module.exports.evalUpdate = function(doc, id, callback) {
  return db.get(id, function(err, doc) {
    if (err != null) {
      return callback(err);
    } else {
      console.log('doc : ' + JSON.stringify(doc));
      return mapDocInRules(doc, id, function(err, mapResults) {
        if (err != null) {
          return callback(err);
        } else {
          return selectInPlug(id, function(err, selectResults) {
            if (err != null) {
              return callback(err);
            } else {
              console.log('select results : ' + JSON.stringify(selectResults));
              return updateProcess(id, mapResults, selectResults, function(err, res) {
                return callback(err, res);
              });
            }
          });
        }
      });
    }

    /*async.eachSeries mapResults, updateResults, (err) ->
        console.log 'mapping results : ' + JSON.stringify mapResults
        callback err, mapResults
     */
  });
};

insertResults = function(mapResult, callback) {
  return async.series([
    function(_callback) {
      if (mapResult.docID != null) {
        return plug.insertDoc(mapResult.docID, mapResult.shareID, mapResult.userDesc, function(err) {
          if (err == null) {
            console.log("doc " + mapResult.docID + " inserted in PlugDB");
          }
          if (err != null) {
            return _callback(err);
          } else {
            return _callback(null);
          }
        });
      } else {
        return _callback(null);
      }
    }, function(_callback) {
      if (mapResult.userID != null) {
        return plug.insertUser(mapResult.userID, mapResult.shareID, mapResult.userDesc, function(err) {
          if (err == null) {
            console.log("user " + mapResult.userID + " inserted in PlugDB");
          }
          if (err != null) {
            return _callback(err);
          } else {
            return _callback(null);
          }
        });
      } else {
        return _callback(null);
      }
    }
  ], function(err) {
    return callback(err);
  });
};

deleteResults = function(select, callback) {
  return async.series([
    function(_callback) {
      if (select.doc != null) {
        return plug.deleteMatch(plug.USERS, select.doc.idPlug, select.doc.shareID, function(err, res) {
          if (err != null) {
            return _callback(err);
          } else {
            if ((res != null) && res.length > 0) {
              return plug.deleteDoc(select.doc.idPlug, function(err) {
                return _callback(err, res);
              });
            } else {
              return _callback(null);
            }
          }
        });
      }
    }, function(_callback) {
      if (select.user != null) {
        return plug.deleteMatch(plug.DOCS, select.user.idPlug, select.user.shareID, function(err, res) {
          if (err != null) {
            return _callback(err);
          } else {
            if ((res != null) && res.length > 0) {
              return plug.deleteDoc(select.user.idPlug, function(err) {
                return _callback(err, res);
              });
            } else {
              return _callback(null);
            }
          }
        });
      }
    }
  ], function(err, results) {
    return callback(err, results);
  });
};

updateResults = function(mapResult, callback) {
  return async.series([
    function(_callback) {
      if (mapResult.docID != null) {
        return plug.insertDoc(mapResult.docID, mapResult.shareID, mapResult.userDesc, function(err) {
          if (err == null) {
            console.log("doc " + mapResult.docID + " inserted in PlugDB");
          }
          if (err != null) {
            return _callback(err);
          } else {
            return _callback(null);
          }
        });
      } else {
        return _callback(null);
      }
    }, function(_callback) {
      if (mapResult.userID != null) {
        return plug.insertUser(mapResult.userID, mapResult.shareID, mapResult.userDesc, function(err) {
          if (err == null) {
            console.log("user " + mapResult.userID + " inserted in PlugDB");
          }
          if (err != null) {
            return _callback(err);
          } else {
            return _callback(null);
          }
        });
      } else {
        return _callback(null);
      }
    }
  ], function(err) {
    return callback(err);
  });
};

selectInPlug = function(id, callback) {
  return async.series([
    function(_callback) {
      return plug.selectDocsByDocID(id, function(err, res) {
        if (err != null) {
          return _callback(err);
        } else {
          return _callback(null, res);
        }
      });
    }, function(_callback) {
      return plug.selectUsersByUserID(id, function(err, res) {
        if (err != null) {
          return _callback(err);
        } else {
          return _callback(null, res);
        }
      });
    }
  ], function(err, results) {
    if (results) {
      console.log('tuples select : ' + JSON.stringify(results));
    }
    return callback(err, results);
  });
};

updateProcess = function(id, mapResults, selectResults, callback) {
  var evalUpdate, existDocOrUser;
  existDocOrUser = function(shareID) {
    var doc, user;
    doc = shareIDInArray(selectResults[0], shareID);
    user = shareIDInArray(selectResults[1], shareID);
    return {
      doc: doc,
      user: user
    };
  };
  evalUpdate = function(rule, _callback) {
    var mapRes, selectResult;
    mapRes = shareIDInArray(mapResults, rule.id);
    selectResult = existDocOrUser(rule.id);
    if (mapRes != null) {
      if ((selectResult.doc != null) || ( selectResult.user != null)) {
        console.log('map and select ok for ' + rule.id);
        _callback(null);
      } else {
        console.log('map ok for ' + rule.id);
        insertResults(mapRes, function(err) {
          if (err != null) {
            return _callback(err);
          } else {
            return matching(mapRes, function(err, acl) {
              if (err) {
                return _callback(err);
              } else {
                if (acl != null) {
                  return sharingProcess(acl, function(err) {
                    return _callback(err);
                  });
                } else {
                  return _callback(null);
                }
              }
            });
          }
        });
      }
    } else {
      if ((selectResult.doc != null) || ( selectResult.user != null)) {
        console.log('select ok for ' + rule.id);
        deleteResults(selectResult, function(err, acls) {
          if (err) {
            return _callback(err);
          } else if (acls != null) {
            return startShares(acls, function(err) {
              return _callback(err);
            });
          } else {
            return _callback(null);
          }
        });
      } else {
        console.log('map and select not ok for ' + rule.id);
        _callback(null);
      }
    }
    return _callback();
  };
  return async.eachSeries(rules, evalUpdate, function(err) {
    return callback(err);
  });
};

module.exports.selectDocPlug = function(id, callback) {
  return plug.selectSingleDoc(id, function(err, tuple) {
    return callback(err, tuple);
  });
};

module.exports.selectUserPlug = function(id, callback) {
  return plug.selectSingleUser(id, function(err, tuple) {
    return callback(err, tuple);
  });
};

mapDocInRules = function(doc, id, callback) {
  var evalRule;
  evalRule = function(rule, _callback) {
    var filterDoc, filterUser, mapResult, saveResult;
    mapResult = {
      docID: null,
      userID: null,
      shareID: null,
      userParams: null
    };
    saveResult = function(id, shareID, userParams, isDoc) {
      if (isDoc) {
        mapResult.docID = id;
      } else {
        mapResult.userID = id;
      }
      mapResult.shareID = shareID;
      return mapResult.userParams = userParams;
    };
    filterDoc = rule.filterDoc;
    filterUser = rule.filterUser;
    return mapDoc(doc, id, rule.id, filterDoc, function(docMaped) {
      if (docMaped) {
        console.log('doc maped !! ');
      }
      if (docMaped) {
        saveResult(id, rule.id, filterDoc.userParam, true);
      }
      return mapDoc(doc, id, rule.id, filterUser, function(userMaped) {
        if (userMaped) {
          console.log('user maped !! ');
        }
        if (userMaped) {
          saveResult(id, rule.id, filterUser.userParam, false);
        }
        if ((mapResult.docID == null) && (mapResult.userID == null)) {
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
    console.log('mapResults : ' + JSON.stringify(mapResults));
    return async.mapSeries(mapResults, matching, function(err, acls) {
      return callback(err, acls);
    });
  } else {
    return callback(null);
  }
};

matching = function(mapResult, callback) {
  var id, matchType;
  console.log('go match : ' + JSON.stringify(mapResult));
  if (mapResult.docID != null) {
    matchType = plug.USERS;
    id = mapResult.docID;
  } else if (mapResult.userID != null) {
    matchType = plug.DOCS;
    id = mapResult.userID;
  } else {
    callback(null);
  }
  return plug.matchAll(matchType, id, mapResult.shareID, function(err, acl) {
    return callback(err, acl);
  });
};

startShares = function(acls, callback) {
  return async.each(acls, sharingProcess, function(err) {
    return callback(err);
  });
};

sharingProcess = function(share, callback) {
  console.log('share : ' + JSON.stringify(share));
  if ((share != null) && (share.users != null)) {
    return async.each(share.users, function(user, _callback) {
      return getCozyAddressFromUserID(user.userID, function(err, url) {
        user.target = url;
        return userSharing(share.shareID, user, share.docIDs, function(err) {
          if (err != null) {
            return _callback(err);
          } else {
            return _callback(null);
          }
        });
      });
    }, function(err) {
      return callback(err);
    });
  } else {
    return callback(null);
  }
};

userSharing = function(shareID, user, ids, callback) {
  var replicationID, rule;
  console.log('share with user : ' + JSON.stringify(user));
  rule = getRuleById(shareID);
  if (rule != null) {
    replicationID = getRepID(rule.activeReplications, user.userID);
    if (replicationID != null) {
      return removeReplication(rule, replicationID, function(err) {
        if (err != null) {
          return callback(err);
        } else {
          return shareDocs(user, ids, rule, function(err) {
            return callback(err);
          });
        }
      });
    } else {
      return shareDocs(user, ids, rule, function(err) {
        return callback(err);
      });
    }
  } else {
    return callback(null);
  }
};

shareDocs = function(user, ids, rule, callback) {
  return replicateDocs(user.target, ids, function(err, repID) {
    if (err != null) {
      return callback(err);
    } else {
      return saveReplication(rule, user.userID, repID, function(err) {
        return callback(err);
      });
    }
  });
};

replicateDocs = function(target, ids, callback) {
  var couchClient, couchTarget, repSourceToTarget, repTargetToSource, sourceURL, targetURL;
  console.log('lets replicate ' + JSON.stringify(ids + ' on target ' + target));
  couchClient = request.newClient("http://localhost:5984");
  sourceURL = "http://192.168.50.4:5984/cozy";
  targetURL = "http://pzjWbznBQPtfJ0es6cvHQKX0cGVqNfHW:NPjnFATLxdvzLxsFh9wzyqSYx4CjG30U@192.168.50.5:5984/cozy";
  couchTarget = request.newClient(targetURL);
  repSourceToTarget = {
    source: "cozy",
    target: targetURL,
    continuous: true,
    doc_ids: ids
  };
  repTargetToSource = {
    source: "cozy",
    target: sourceURL,
    continuous: true,
    doc_ids: ids
  };
  return couchClient.post("_replicate", repSourceToTarget, function(err, res, body) {
    var replicationID;
    if (err != null) {
      return callback(err);
    } else if (!body.ok) {
      console.log(JSON.stringify(body));
      return callback(body);
    } else {
      console.log('Replication from source suceeded \o/');
      console.log(JSON.stringify(body));
      replicationID = body._local_id;
      return couchTarget.post("_replicate", repTargetToSource, function(err, res, body) {
        if (err != null) {
          return callback(err);
        } else if (!body.ok) {
          console.log(JSON.stringify(body));
          return callback(body);
        } else {
          console.log('Replication from target suceeded \o/');
          console.log(JSON.stringify(body));
          return callback(err, replicationID);
        }
      });
    }
  });
};

updateActiveRep = function(shareID, activeReplications, callback) {
  return db.get(shareID, function(err, doc) {
    if (err != null) {
      return callback(err);
    } else {
      doc.activeReplications = activeReplications;
      return db.save(shareID, doc, function(err, res) {
        return callback(err);
      });
    }
  });
};

saveReplication = function(rule, userID, replicationID, callback) {
  if ((rule != null) && (replicationID != null)) {
    if (rule.activeReplications != null) {
      rule.activeReplications.push({
        userID: userID,
        replicationID: replicationID
      });
      return updateActiveRep(rule.id, rule.activeReplications, function(err) {
        return callback(err);
      });
    } else {
      rule.activeReplications = [
        {
          userID: userID,
          replicationID: replicationID
        }
      ];
      return updateActiveRep(rule.id, rule.activeReplications, function(err) {
        return callback(err);
      });
    }
  } else {
    return callback(null);
  }
};

removeReplication = function(rule, replicationID, callback) {
  if ((rule != null) && (replicationID != null)) {
    return cancelReplication(replicationID, function(err) {
      var i, rep, _i, _len, _ref;
      if (err != null) {
        return callback(err);
      } else {
        if (rule.activeReplications != null) {
          _ref = rule.activeReplications;
          for (i = _i = 0, _len = _ref.length; _i < _len; i = ++_i) {
            rep = _ref[i];
            if (rep.replicationID === replicationID) {
              rule.activeReplications.splice(i, 1);
              updateActiveRep(rule.id, rule.activeReplications, function(err) {
                if (err != null) {
                  return callback(err);
                }
              });
            }
          }
          return callback(null);
        } else {
          return updateActiveRep(rule.id, [], function(err) {
            return callback(err);
          });
        }
      }
    });
  } else {
    return callback(null);
  }
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

getActiveTasks = function(client, callback) {
  return client.get("_active_tasks", function(err, res, body) {
    var repIds, task, _i, _len;
    if ((err != null) || (body.length == null)) {
      return callback(err);
    } else {
      for (_i = 0, _len = body.length; _i < _len; _i++) {
        task = body[_i];
        if (task.replication_id) {
          repIds = task.replication_id;
        }
      }
      return callback(null, repIds);
    }
  });
};

module.exports.createRule = function(doc, callback) {};

module.exports.deleteRule = function(doc, callback) {};

module.exports.updateRule = function(doc, callback) {};

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

module.exports.insertRules = function(callback) {
  var insertShare;
  insertShare = function(rule, _callback) {
    return plug.insertShare(rule.id, '', function(err) {
      return _callback(err);
    });
  };
  return async.eachSeries(rules, insertShare, function(err) {
    if (err == null) {
      console.log('rules inserted');
    }
    return callback(err);
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

getRepID = function(array, userID) {
  var activeRep, _i, _len;
  if (array != null) {
    for (_i = 0, _len = array.length; _i < _len; _i++) {
      activeRep = array[_i];
      if (activeRep.userID === userID) {
        return activeRep.replicationID;
      }
    }
  }
};

shareIDInArray = function(array, shareID) {
  var ar, _i, _len;
  if (array != null) {
    for (_i = 0, _len = array.length; _i < _len; _i++) {
      ar = array[_i];
      if (ar.shareID === shareID) {
        return ar;
      }
    }
  }
  return null;
};

getRuleById = function(shareID, callback) {
  var rule, _i, _len;
  for (_i = 0, _len = rules.length; _i < _len; _i++) {
    rule = rules[_i];
    if (rule.id === shareID) {
      return rule;
    }
  }
};

removeNullValues = function(array) {
  var i, _i, _ref, _results;
  if (array != null) {
    _results = [];
    for (i = _i = _ref = array.length - 1; _ref <= 0 ? _i <= 0 : _i >= 0; i = _ref <= 0 ? ++_i : --_i) {
      if (array[i] === null) {
        _results.push(array.splice(i, 1));
      } else {
        _results.push(void 0);
      }
    }
    return _results;
  }
};

removeDuplicates = function(array) {
  var key, res, value, _i, _ref, _results;
  if (array.length === 0) {
    return [];
  }
  res = {};
  for (key = _i = 0, _ref = array.length - 1; 0 <= _ref ? _i <= _ref : _i >= _ref; key = 0 <= _ref ? ++_i : --_i) {
    res[array[key]] = array[key];
  }
  _results = [];
  for (key in res) {
    value = res[key];
    _results.push(value);
  }
  return _results;
};

convertTuples = function(tuples, callback) {
  var array, res, tuple, _i, _len;
  if (tuples != null) {
    array = [];
    for (_i = 0, _len = tuples.length; _i < _len; _i++) {
      tuple = tuples[_i];
      res = {
        shareID: tuple[2],
        userParams: tuple[3]
      };
      array.push(res);
    }
    return array;
  }
};
