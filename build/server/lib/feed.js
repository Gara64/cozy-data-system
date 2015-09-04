// Generated by CoffeeScript 1.9.3
var Client, Feed, S, async, client, fs, log, setCouchCredentials, thumb,
  bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

fs = require('fs');

S = require('string');

async = require('async');

Client = require('request-json').JsonClient;

client = null;

thumb = require('./thumb');

log = require('printit')({
  prefix: 'feed'
});

setCouchCredentials = function() {
  var data, lines;
  if (process.env.NODE_ENV === 'production') {
    data = fs.readFileSync('/etc/cozy/couchdb.login');
    lines = S(data.toString('utf8')).lines();
    return client.setBasicAuth(lines[0], lines[1]);
  }
};

module.exports = Feed = (function() {
  var deleted_ids;

  Feed.prototype.db = void 0;

  Feed.prototype.feed = void 0;

  Feed.prototype.axonSock = void 0;

  deleted_ids = {};

  function Feed() {
    this._onChange = bind(this._onChange, this);
    this.publish = bind(this.publish, this);
    this.logger = require('printit')({
      date: true,
      prefix: 'helper/db_feed'
    });
  }

  Feed.prototype.initialize = function(server) {
    this.startPublishingToAxon();
    return server.on('close', (function(_this) {
      return function() {
        _this.stopListening();
        if (_this.axonSock != null) {
          return _this.axonSock.close();
        }
      };
    })(this));
  };

  Feed.prototype.startPublishingToAxon = function() {
    var axon, axonPort;
    axon = require('axon');
    this.axonSock = axon.socket('pub-emitter');
    axonPort = parseInt(process.env.AXON_PORT || 9105);
    this.axonSock.bind(axonPort);
    this.logger.info('Pub server started');
    this.axonSock.sock.on('connect', (function(_this) {
      return function() {
        return _this.logger.info("An application connected to the change feeds");
      };
    })(this));
    return this.axonSock.sock.on('message', (function(_this) {
      return function(event, id) {
        return _this._publish(event.toString(), id.toString());
      };
    })(this));
  };

  Feed.prototype.startListening = function(db) {
    var couchUrl;
    this.stopListening();
    couchUrl = "http://" + db.connection.host + ":" + db.connection.port + "/";
    client = new Client(couchUrl);
    setCouchCredentials();
    this.feed = db.changes({
      since: 'now'
    });
    this.feed.on('change', this._onChange);
    this.feed.on('error', (function(_this) {
      return function(err) {
        _this.logger.error("Error occured with feed : " + err.stack);
        return _this.stopListening();
      };
    })(this));
    return this.db = db;
  };

  Feed.prototype.stopListening = function() {
    if (this.feed != null) {
      this.feed.stop();
      this.feed.removeAllListeners('change');
      this.feed = null;
    }
    if (this.db != null) {
      return this.db = null;
    }
  };

  Feed.prototype.publish = function(event, id) {
    return this._publish(event, id);
  };

  Feed.prototype._publish = function(event, id) {
    this.logger.info("Publishing " + event + " " + id);
    if (this.axonSock != null) {
      return this.axonSock.emit(event, id);
    }
  };

  Feed.prototype._onChange = function(change) {
    var dbName, isCreation, operation, requestPath;
    if (change.deleted) {
      dbName = process.env.DB_NAME || 'cozy';
      requestPath = "/" + dbName + "/" + change.id + "?revs_info=true&open_revs=all";
      return client.get(requestPath, (function(_this) {
        return function(err, res, doc) {
          var ref, ref1, removeBinary;
          if ((doc != null ? (ref = doc[0]) != null ? (ref1 = ref.ok) != null ? ref1.docType : void 0 : void 0 : void 0) != null) {
            doc = doc[0].ok;
            _this._publish((doc.docType.toLowerCase()) + ".delete", change.id);
          }
          if (doc.binary != null) {
            removeBinary = function(name, callback) {
              var binary, file;
              file = doc.binary[name];
              binary = file.id;
              return _this.db.view('binary/byDoc', {
                key: binary
              }, function(err, res) {
                if (err) {
                  return callback(err);
                } else if ((res != null ? res.length : void 0) === 0) {
                  return _this.db.get(binary, function(err, doc) {
                    if (err) {
                      return callback(err);
                    }
                    if (doc) {
                      return _this.db.remove(doc._id, doc._rev, function(err, doc) {
                        if (err == null) {
                          _this._publish("binary.delete", doc.id);
                        }
                        return callback(err);
                      });
                    } else {
                      return callback();
                    }
                  });
                } else {
                  return callback();
                }
              });
            };
            return async.each(Object.keys(doc.binary), removeBinary, function(err) {
              if (err) {
                return log.error(err);
              }
            });
          }
        };
      })(this));
    } else {
      isCreation = change.changes[0].rev.split('-')[0] === '1';
      operation = isCreation ? 'create' : 'update';
      return this.db.get(change.id, (function(_this) {
        return function(err, doc) {
          var doctype, ref;
          if (err) {
            _this.logger.error(err);
          }
          doctype = doc != null ? (ref = doc.docType) != null ? ref.toLowerCase() : void 0 : void 0;
          if (doctype) {
            _this._publish(doctype + "." + operation, doc._id);
          }
          if (doctype === 'file') {
            return _this.db.get(change.id, function(err, file) {
              var ref1;
              if (file["class"] === 'image' && (((ref1 = file.binary) != null ? ref1.file : void 0) != null) && !file.binary.thumb) {
                return thumb.create(file, false);
              }
            });
          }
        };
      })(this));
    }
  };

  return Feed;

})();

module.exports = new Feed();
