// Generated by CoffeeScript 1.10.0
var Sharing, addAccess, async, db, randomString;

Sharing = require('../lib/sharing');

async = require('async');

addAccess = require('../lib/token').addAccess;

db = require('../helpers/db_connect_helper').db_connect();

randomString = function(length) {
  var string;
  string = "";
  while (string.length < length) {
    string = string + Math.random().toString(36).substr(2);
  }
  return string.substr(0, length);
};

module.exports.create = function(req, res, next) {
  var err, share;
  share = req.body;
  if (share == null) {
    err = new Error("Bad request");
    err.status = 400;
    return next(err);
  } else {
    return db.save(share, function(err, res) {
      if (err != null) {
        return next(err);
      } else {
        share.id = res._id;
        req.share = share;
        return next();
      }
    });
  }
};

module.exports.requestTarget = function(req, res, next) {
  var err, share;
  if (req.share == null) {
    err = new Error("Bad request");
    err.status = 400;
    return next(err);
  } else {
    share = req.share;
    return Sharing.getDomain(function(err, domain) {
      var request;
      if (err != null) {
        return next(new Error('No instance domain set'));
      } else {
        request = {
          shareID: share.id,
          desc: share.desc,
          sync: share.sync,
          hostUrl: domain
        };
        console.log('request : ' + JSON.stringify(request));
        return async.each(share.targets, function(target, callback) {
          request.url = target.url;
          return Sharing.notifyTarget(target.url, request, function(err, result, body) {
            if (err != null) {
              return callback(err);
            } else if ((result != null ? result.statusCode : void 0) == null) {
              err = new Error("Bad request");
              err.status = 400;
              return callback(err);
            } else {
              res.send(result.statusCode, body);
              return callback();
            }
          });
        }, function(err) {
          if (err != null) {
            return next(err);
          }
        });
      }
    });
  }
};

module.exports.handleAnswer = function(req, res, next) {

  /* Params must contains :
  id (usersharing)
  shareID
  accepted
  targetUrl
  docIDs
  hostUrl
   */
  var access, err, params;
  if (req.body == null) {
    err = new Error("Bad request");
    err.status = 400;
    next(err);
  }
  params = req.body;
  if (params.accepted === true) {
    access = {
      login: params.shareID,
      password: randomString(32),
      id: params.id,
      permissions: params.docIDs
    };
    return addAccess(access, function(err, doc) {
      if (err != null) {
        return next(err);
      }
      params.pwd = access.password;
      req.params = params;
      return next();
    });
  } else {
    return db.remove(req.params.id, function(err, res) {
      if (err != null) {
        return next(err);
      }
      req.params = params;
      return next();
    });
  }
};

module.exports.sendAnswer = function(req, res, next) {
  var answer, err, params;
  console.log('params ' + JSON.stringify(req.params));
  params = req.body;
  if (params == null) {
    err = new Error("Bad request");
    err.status = 400;
    return next(err);
  } else {
    answer = {
      shareID: params.shareID,
      url: params.url,
      accepted: params.accepted,
      pwd: params.pwd
    };
    return Sharing.answerHost(params.hostUrl, answer, function(err, result, body) {
      if (err != null) {
        return next(err);
      } else if ((result != null ? result.statusCode : void 0) == null) {
        err = new Error("Bad request");
        err.status = 400;
        return next(err);
      } else {
        return res.send(result.statusCode, body);
      }
    });
  }
};

module.exports.validateTarget = function(req, res, next) {
  var answer, err;
  console.log('answer : ' + JSON.stringify(req.body));
  answer = req.body;
  if (answer == null) {
    err = new Error("Bad request");
    err.status = 400;
    return next(err);
  } else {
    return db.get(answer.shareID, function(err, doc) {
      var i, j, len, ref, t, target;
      if (err != null) {
        return next(err);
      }
      console.log('share doc : ' + JSON.stringify(doc));
      ref = doc.targets;
      for (j = 0, len = ref.length; j < len; j++) {
        t = ref[j];
        if (t.url = answer.url) {
          target = t;
        }
      }
      if (target == null) {
        err = new Error(answer.url + " not found for this sharing");
        err.status = 404;
        return next(err);
      } else {
        if (answer.accepted) {
          target.pwd = answer.pwd;
        } else {
          i = doc.targets.indexOf(target);
          doc.targets.splice(i, 1);
        }
        return db.merge(doc._id, doc, function(err, res) {
          var params;
          if (err != null) {
            return next(err);
          }
          params = {
            pwd: answer.pwd,
            url: answer.url,
            id: doc._id,
            docIDs: doc.docIDs,
            sync: doc.sync
          };
          req.params = params;
          return next();
        });
      }
    });
  }
};

module.exports.update = function(req, res, next) {
  return db.merge(req.doc._id, req.doc, function(err, res) {
    var params;
    if (err != null) {
      return next(err);
    } else {
      params = {
        pwd: req.answer.pwd,
        url: req.answer.url,
        id: shareDoc.id,
        docIDs: shareDoc.docIDs,
        sync: shareDoc.isSync
      };
      return next();
    }
  });
};

module.exports.replicate = function(req, res, next) {
  var params;
  params = req.params;
  if (params.pwd != null) {
    return Sharing.replicateDocs(params, function(err, repID) {
      if (err != null) {
        next(err);
      } else if (repID == null) {
        err = new Error("Replication failed");
        err.status = 500;
        next(err);
      }
      if (repID != null) {
        return res.send(200, {
          success: true
        });
      }
    });
  } else {
    return res.send(200, {
      success: true
    });
  }
};