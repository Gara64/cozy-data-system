// Generated by CoffeeScript 1.10.0
var db, deleteFiles, downloader, fs, log, multiparty, querystring;

fs = require("fs");

querystring = require("querystring");

multiparty = require('multiparty');

log = require('printit')({
  date: true,
  prefix: 'attachment'
});

db = require('../helpers/db_connect_helper').db_connect();

deleteFiles = require('../helpers/utils').deleteFiles;

downloader = require('../lib/downloader');

module.exports.add = function(req, res, next) {
  var fields, form, nofile;
  form = new multiparty.Form();
  form.parse(req);
  nofile = true;
  fields = {};
  form.on('part', function(part) {
    var fileData, name, stream;
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
        name: querystring.escape(name),
        "content-type": part.headers['content-type']
      };
      log.info("attachment " + name + " ready for storage");
      stream = db.saveAttachment(req.doc, fileData, function(err) {
        if (err) {
          console.log("[Attachment] err: " + JSON.stringify(err));
          return form.emit('error', err);
        } else {
          log.info("Attachment " + name + " saved to Couch.");
          res.send(201, {
            success: true
          });
          return next();
        }
      });
      return part.pipe(stream);
    }
  });
  form.on('progress', function(bytesReceived, bytesExpected) {});
  form.on('error', function(err) {
    return next(err);
  });
  return form.on('close', function() {
    var err;
    if (nofile) {
      err = new Error('no file sent');
      err.status = 400;
      return next(err);
    }
  });
};

module.exports.get = function(req, res, next) {
  var id, name, request;
  name = req.params.name;
  id = req.doc.id;
  return request = downloader.download(id, name, function(err, stream) {
    var length, type;
    if (err) {
      return next(err);
    } else {
      if (req.headers['range'] != null) {
        res.setHeader('range', req.headers['range']);
      }
      length = req.doc._attachments[name].length;
      type = req.doc._attachments[name]['content-type'];
      res.setHeader('Content-Length', length);
      if (type != null) {
        res.setHeader('Content-Type', type);
      }
      req.once('close', function() {
        return request.abort();
      });
      return stream.pipe(res);
    }
  });
};

module.exports.remove = function(req, res, next) {
  var name;
  name = req.params.name;
  return db.removeAttachment(req.doc, name, function(err) {
    if (err) {
      return next(err);
    } else {
      res.send(204, {
        success: true
      });
      return next();
    }
  });
};
