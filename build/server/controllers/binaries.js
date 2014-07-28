// Generated by CoffeeScript 1.7.1
var db, dbHelper, deleteFiles, downloader, fs, log, multiparty;

fs = require("fs");

multiparty = require('multiparty');

log = require('printit')({
  date: true,
  prefix: 'binaries'
});

db = require('../helpers/db_connect_helper').db_connect();

deleteFiles = require('../helpers/utils').deleteFiles;

dbHelper = require('../lib/db_remove_helper');

downloader = require('../lib/downloader');

module.exports.add = function(req, res, next) {
  var fields, form, nofile;
  form = new multiparty.Form({
    autoFields: false,
    autoFiles: false
  });
  form.parse(req);
  nofile = true;
  fields = {};
  form.on('part', function(part) {
    var attachBinary, binary, fileData, name, _ref;
    if (part.filename == null) {
      fields[part.name] = '';
      part.on('data', function(buffer) {
        return fields[part.name] = buffer.toString();
      });
      return part.resume();
    } else {
      nofile = false;
      if (fields.name != null) {
        name = fields.name;
      } else {
        name = part.filename;
      }
      fileData = {
        name: 'file',
        "content-type": part.headers['content-type']
      };
      attachBinary = function(binary) {};
      if (((_ref = req.doc.binary) != null ? _ref[name] : void 0) != null) {
        return db.get(req.doc.binary[name].id, function(err, binary) {
          return attachBinary(binary);
        });
      } else {
        binary = {
          docType: "Binary"
        };
        return db.save(binary, function(err, binDoc) {
          var stream;
          binary = binDoc;
          log.info("binary " + name + " ready for storage");
          stream = db.saveAttachment(binary, fileData, function(err, binDoc) {
            var bin, binList;
            if (err) {
              log.error("" + (JSON.stringify(err)));
              return form.emit('error', new Error(err.error));
            } else {
              log.info("Binary " + name + " stored in Couchdb");
              bin = {
                id: binDoc.id,
                rev: binDoc.rev
              };
              if (req.doc.binary) {
                binList = req.doc.binary;
              } else {
                binList = {};
              }
              binList[name] = bin;
              return db.merge(req.doc._id, {
                binary: binList
              }, function(err) {
                return res.send(201, {
                  success: true
                });
              });
            }
          });
          return part.pipe(stream);
        });
      }
    }
  });
  form.on('progress', function(bytesReceived, bytesExpected) {});
  form.on('error', function(err) {
    return next(err);
  });
  return form.on('close', function() {
    if (nofile) {
      res.send(400, {
        error: 'No file sent'
      });
    }
    return next();
  });
};

module.exports.get = function(req, res, next) {
  var err, id, name, stream;
  name = req.params.name;
  if (req.doc.binary && req.doc.binary[name]) {
    id = req.doc.binary[name].id;
    return stream = downloader.download(id, 'file', function(err, stream) {
      if (err && (err.error = "not_found")) {
        err = new Error("not found");
        err.status = 404;
        next(err);
      } else if (err) {
        next(new Error(err.error));
      }
      if (req.headers['range'] != null) {
        stream.setHeader('range', req.headers['range']);
      }
      return stream.pipe(res);
    });
  } else {
    err = new Error("not found");
    err.status = 404;
    return next(err);
  }
};

module.exports.remove = function(req, res, next) {
  var err, id, name;
  name = req.params.name;
  if (req.doc.binary && req.doc.binary[name]) {
    id = req.doc.binary[name].id;
    delete req.doc.binary[name];
    if (req.doc.binary.length === 0) {
      delete req.doc.binary;
    }
    return db.save(req.doc, function(err) {
      return db.get(id, function(err, binary) {
        if (binary != null) {
          return dbHelper.remove(binary, function(err) {
            if ((err != null) && (err.error = "not_found")) {
              err = new Error("not found");
              err.status = 404;
              return next(err);
            } else if (err) {
              console.log("[Attachment] err: " + JSON.stringify(err));
              return next(new Error(err.error));
            } else {
              res.send(204, {
                success: true
              });
              return next();
            }
          });
        } else {
          err = new Error("not found");
          err.status = 404;
          return next(err);
        }
      });
    });
  } else {
    err = new Error("no binary ID is provided");
    err.status = 400;
    return next(err);
  }
};
