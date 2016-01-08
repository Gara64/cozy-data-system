// Generated by CoffeeScript 1.10.0
var BATCH_SIZE, FETCH_AT_ONCE_FOR_REINDEX, addBatch, async, base, batchCounter, batchInProgress, checkpointDocTypeRev, checkpointSeqNumber, cleanup, commonIndexFields, db, dequeue, finishReindexing, forgetDoc, getDocs, getStatus, groupChangesByDoctypes, indexQueue, indexdefinitions, indexdefinitionsID, indexer, initializeReindexing, locker, log, maybeReindexDocType, path, persistentDirectory, registerDefaultIndexes, reindexChanges, resumeReindexing, saveStatus;

path = require('path');

persistentDirectory = process.env.APPLICATION_PERSISTENT_DIRECTORY;

if (persistentDirectory) {
  if ((base = process.env).INDEXES_PATH == null) {
    base.INDEXES_PATH = path.join(persistentDirectory, 'indexes');
  }
}

indexer = require('cozy-indexer');

db = require('../helpers/db_connect_helper').db_connect();

async = require('async');

locker = require('../lib/locker');

log = require('printit')({
  date: true,
  prefix: 'indexer'
});

indexQueue = {};

batchInProgress = false;

BATCH_SIZE = 10;

batchCounter = 1;

indexdefinitions = {};

indexdefinitionsID = {};

FETCH_AT_ONCE_FOR_REINDEX = BATCH_SIZE;

commonIndexFields = {
  "docType": {
    filter: true,
    searchable: false
  },
  "tags": {
    filter: true
  }
};

forgetDoc = locker.wrap('indexfile', indexer.forget);

addBatch = locker.wrap('indexfile', indexer.addBatch);

cleanup = locker.wrap('indexfile', indexer.cleanup);


/**
 * Initialize the indexer
 *
 * @return (callback) when initialization is complete
 */

exports.initialize = function(callback) {
  return async.waterfall([
    function(callback) {
      return indexer.store.open(callback);
    }, function(callback) {
      var query;
      query = {
        include_docs: true
      };
      return db.view("indexdefinition/all", query, function(err, rows) {
        var definitionDocument, docType, i, k, len, row, v;
        if (err) {
          return callback(err);
        }
        for (i = 0, len = rows.length; i < len; i++) {
          row = rows[i];
          docType = row.doc.targetDocType;
          definitionDocument = row.doc;
          for (k in commonIndexFields) {
            v = commonIndexFields[k];
            definitionDocument.ftsIndexedFields[k] = v;
          }
          indexdefinitions[docType] = definitionDocument;
          indexdefinitionsID[row.id] = docType;
        }
        return registerDefaultIndexes(callback);
      });
    }, function(callback) {
      var docTypes;
      docTypes = Object.keys(indexdefinitions);
      return async.eachSeries(docTypes, maybeReindexDocType, callback);
    }, function(callback) {
      return indexer.store.get('indexedseq', function(err, seqno) {
        if (err) {
          return callback(err);
        }
        return reindexChanges(seqno, callback);
      });
    }
  ], callback);
};


/**
 * Get a batch from the queue and index it
 *
 */

dequeue = function() {
  var batchName, docType, docs, maxseqno, options;
  if (batchInProgress) {
    return null;
  }
  for (docType in indexQueue) {
    docs = indexQueue[docType];
    if (!(docs.length > 0)) {
      continue;
    }
    docs = docs.slice(0, BATCH_SIZE);
    indexQueue[docType] = docs.slice(BATCH_SIZE);
    batchInProgress = true;
    break;
  }
  if (!batchInProgress) {
    return null;
  }
  options = indexdefinitions[docType].ftsIndexedFields;
  maxseqno = docs[docs.length - 1]._seqno;
  batchName = "batch " + (batchCounter++);
  log.info("add " + batchName + " of " + docs.length + " " + docType);
  return addBatch(docs, options, function(err) {
    log.info(batchName + " done " + ((err != null ? err.stack : void 0) || 'success'));
    return checkpointSeqNumber(maxseqno, function(err) {
      if (err) {
        log.error("checkpoint error", err);
      }
      batchInProgress = false;
      return setImmediate(dequeue);
    });
  });
};


/**
 * Destroy the index completely (used for tests)
 *
 */

exports.cleanup = function(callback) {
  return cleanup(callback);
};


/**
 * To be called every time a document is updated
 * used in lib/feed
 *
 */

exports.onDocumentUpdate = function(doc, seqno) {
  var docType, ref;
  docType = (ref = doc.docType) != null ? typeof ref.toLowerCase === "function" ? ref.toLowerCase() : void 0 : void 0;
  if (docType in indexdefinitions) {
    doc._seqno = seqno;
    if (indexQueue[docType] == null) {
      indexQueue[docType] = [];
    }
    indexQueue[docType].push(doc);
    return setImmediate(dequeue);
  }
};


/**
 * To be called every time a document is deleted
 * used in lib/feed
 *
 */

exports.onDocumentDelete = function(doc, seqno) {
  var docType;
  if (doc.docType === 'indexdefinition') {
    docType = indexdefinitionsID[doc._id];
    return delete indexdefinitions[docType];
  } else if (doc.docType in indexdefinitions) {
    return forgetDoc(doc._id, function() {
      return log.info("doc" + doc._id + " unindexed");
    });
  }
};


/**
 * Perform a search in the index
 *
 * @params docType {array} docTypes to search in, empty for all
 * @params options {object} query options
 * @params options.query {mixed} the search terms
 * @params options.numPage {number} page number
 * @params options.pageSize {number} number of result by page
 * @params options.facets {object} see cozy-indexer doc
 * @params options.filter {object} see cozy-indexer doc
 *
 * @return (callback) {object} see cozy-indexer doc
 *
 */

exports.search = function(docTypes, options, callback) {
  var params;
  params = {
    offset: options.numPage || 0,
    pageSize: options.numByPage || 10
  };
  if (typeof options.query === 'string') {
    params.search = {
      "*": [options.query]
    };
  } else if (Array.isArray(options.query)) {
    params.search = {
      "*": options.query
    };
  } else {
    params.search = options.query;
  }
  if (options.facets) {
    params.facets = options.facets;
  }
  if (options.filter) {
    params.filter = options.filter;
  }
  if (docTypes.length > 0) {
    if (params.filter == null) {
      params.filter = {};
    }
    params.filter.docType = docTypes.map(function(t) {
      return [t, t];
    });
  }
  return indexer.search(params, callback);
};


/**
 * Register the indexdefintion for a docType
 *
 * @params docType {string} docType to register for
 * @params indexdefinition {object} a map of field to index rules
 *
 * @return (callback) after reindexing or 10s, whichever comes first
 *
 */

exports.registerIndexDefinition = function(docType, indexdefinition, callback) {
  var callbackOnce, changed, definitionDocument, existing, field, fieldDef, k, mergedFields, oldFieldDef, ref, v;
  callbackOnce = function(cause) {
    if (callback) {
      callback.apply(this, arguments);
    }
    return callback = null;
  };
  docType = docType.toLowerCase();
  existing = indexdefinitions[docType];
  changed = false;
  if (existing) {
    mergedFields = {};
    ref = existing.ftsIndexedFields;
    for (k in ref) {
      v = ref[k];
      if (!commonIndexFields[k]) {
        mergedFields[k] = v;
      }
    }
    for (field in indexdefinition) {
      fieldDef = indexdefinition[field];
      oldFieldDef = existing.ftsIndexedFields[field];
      mergedFields[field] = indexer.mergeFieldDef(oldFieldDef, fieldDef);
      if (mergedFields[field] !== oldFieldDef) {
        changed = true;
      }
    }
    definitionDocument = existing;
    definitionDocument.ftsIndexedFields = mergedFields;
  } else {
    definitionDocument = {
      docType: "indexdefinition",
      ftsIndexedFields: indexdefinition,
      targetDocType: docType
    };
    changed = true;
  }
  if (changed) {
    return db.save(definitionDocument, function(err, savedDoc) {
      if (err) {
        return callback(err);
      }
      definitionDocument._id = savedDoc.id;
      definitionDocument._rev = savedDoc.rev;
      for (k in commonIndexFields) {
        v = commonIndexFields[k];
        definitionDocument.ftsIndexedFields[k] = v;
      }
      indexdefinitions[docType] = definitionDocument;
      indexdefinitionsID[savedDoc.id] = docType;
      setTimeout(callbackOnce.bind(null, new Error('timeout')), 10000);
      return initializeReindexing(docType, function(err) {
        if (err) {
          return callbackOnce(err);
        }
        return checkpointDocTypeRev(docType, savedDoc.rev, callbackOnce);
      });
    });
  } else {
    log.info("rev is different, but definition not changed");
    return checkpointDocTypeRev(docType, savedDoc.rev, callbackOnce);
  }
};


/**
 * Store the indexdefintion rev within the index file
 *
 * @params docType {string} docType to register for
 * @params rev {string} value to store
 *
 * @return (callback) when done
 *
 */

checkpointDocTypeRev = function(docType, rev, callback) {
  return getStatus(docType, function(err, status) {
    if (err) {
      return callback(err);
    }
    status.rev = rev;
    return saveStatus(docType, status, callback);
  });
};


/**
 * Store the last indexed sequence number within the index file
 *
 * @params seqno {string} value to store
 *
 * @return (callback) when done
 *
 */

checkpointSeqNumber = function(seqno, callback) {
  return indexer.store.set('indexedseq', seqno, callback);
};

groupChangesByDoctypes = function(changes) {
  var byDoctype, change, definition, docType, docs, i, len, out;
  byDoctype = {};
  out = [];
  for (i = 0, len = changes.length; i < len; i++) {
    change = changes[i];
    docType = change.doc.docType;
    definition = indexdefinitions[docType];
    if (definition && !change.deleted) {
      if (!byDoctype[docType]) {
        docs = byDoctype[docType] = [];
        out.push({
          docType: docType,
          docs: docs,
          definition: definition
        });
      }
      byDoctype[docType].push(change.doc);
    }
  }
  return out;
};


/*
 * Recursive function to reindex all docs which have changed since
 * the given seqno
 *
 * @params seqno {number} sequence number to start from
 *
 * @return (callback) when done
 *
 */

reindexChanges = function(seqno, callback) {
  var options;
  options = {
    include_docs: true,
    since: seqno,
    limit: FETCH_AT_ONCE_FOR_REINDEX
  };
  return db.changes(options, function(err, changes) {
    var batches, maxSeqNo;
    if (err) {
      return callback(err);
    }
    if (changes.length < FETCH_AT_ONCE_FOR_REINDEX) {
      return callback(null);
    }
    batches = groupChangesByDoctypes(changes);
    maxSeqNo = changes[changes.length - 1].seq;
    return async.eachSeries(batches, function(arg, next) {
      var definition, docType, docs;
      docs = arg.docs, docType = arg.docType, definition = arg.definition;
      return indexer.addBatch(docs, definition.ftsIndexedFields, next);
    }, function(err) {
      if (err) {
        return callback(err);
      }
      return checkpointSeqNumber(maxSeqNo, function(err) {
        if (err) {
          return callback(err);
        }
        return reindexChanges(maxSeqNo, callback);
      });
    });
  });
};

getDocs = function(docType, skip, limit, callback) {
  docType = docType.toLowerCase();
  return db.view("doctypes/all", {
    key: docType,
    limit: FETCH_AT_ONCE_FOR_REINDEX,
    skip: skip,
    include_docs: true,
    reduce: false
  }, callback);
};

getStatus = function(docType, callback) {
  return indexer.store.get("indexingstatus/" + docType, function(err, status) {
    if (err || !status) {
      status = {
        skip: 0,
        state: "indexing-by-doctype",
        rev: 'no-revision'
      };
    } else if (status) {
      status = JSON.parse(status);
    }
    return callback(null, status);
  });
};

saveStatus = function(docType, status, callback) {
  status = JSON.stringify(status);
  return indexer.store.set("indexingstatus/" + docType, status, callback);
};


/**
 * Reindex a given docType from the beginning
 *
 * @params docType {string} docType to reindex
 *
 * @return (callback) when done
 *
 */

initializeReindexing = function(docType, callback) {
  var definition;
  definition = indexdefinitions[docType];
  return db.info(function(err, infos) {
    var status;
    if (err) {
      return callback(err);
    }
    status = {
      state: "indexing-by-doctype",
      rev: definition._rev,
      skip: 0,
      checkpointedSeqNumber: infos.update_seq
    };
    return saveStatus(docType, status, function(err) {
      if (err) {
        return callback(err);
      }
      return resumeReindexing(docType, status, callback);
    });
  });
};


/**
 * Recursive function to reindex all docs for a given docType
 * get doc in batch of FETCH_AT_ONCE_FOR_REINDEX and add them immediately
 *
 * Note, this function doesn't use the indexQueue used for realtime events
 *
 * @params docType {string} value to store
 * @params definition {object} definition of fields to store
 *
 * @return (callback) when done
 *
 */

resumeReindexing = function(docType, status, callback) {
  var definition;
  definition = indexdefinitions[docType];
  if (status.rev !== definition._rev) {
    log.info("aborting reindex");
    return callback(new Error('abort'));
  }
  return getDocs(docType, status.skip, FETCH_AT_ONCE_FOR_REINDEX, function(err, rows) {
    var docs;
    if (err) {
      return callback(err);
    }
    if (rows.length === 0) {
      return finishReindexing(docType, status, callback);
    }
    docs = rows.toArray();
    return indexer.addBatch(docs, definition.ftsIndexedFields, function(err) {
      if (err) {
        return callback(err);
      }
      status.skip = status.skip + FETCH_AT_ONCE_FOR_REINDEX;
      return saveStatus(docType, status, function(err) {
        var next;
        if (err) {
          return callback(err);
        }
        next = resumeReindexing.bind(null, docType, status, callback);
        return setTimeout(next, 500);
      });
    });
  });
};

finishReindexing = function(docType, status, callback) {
  status.state = 'indexing-by-changes';
  status.skip = 0;
  return saveStatus(docType, status, callback);
};


/**
 * Check if given docType definition is the same we used to index it
 * if not, fire up a reindexing using initializeReindexing
 *
 * @params docType {string} docType to test
 *
 * @return (callback) when done
 *
 */

maybeReindexDocType = function(docType, callback) {
  var definition;
  definition = indexdefinitions[docType];
  return getStatus(docType, function(err, status) {
    log.info("Check index status for " + docType + " :\n    in indexer:" + status.rev + " " + status.state + " " + status.skip + " ,\n    in data-system:" + definition._rev);
    if (status.rev === definition._rev) {
      if (status.state === 'indexing-by-doctype') {
        return resumeReindexing(docType, status, callback);
      } else {
        return setImmediate(callback);
      }
    } else {
      return initializeReindexing(docType, callback);
    }
  });
};


/**
 * [TMP] Register default indexes used by most cozy on October 2015,
 * ie. Folder, File and Note indexes.
 *
 * @return (callback) when done
 *
 */

registerDefaultIndexes = function(callback) {
  var actions, registerFile, registerFolder, registerNote;
  registerNote = function(done) {
    return exports.registerIndexDefinition('note', {
      title: {
        nGramLength: {
          gte: 1,
          lte: 2
        },
        stemming: true,
        weight: 5,
        fieldedSearch: false
      },
      content: {
        nGramLength: {
          gte: 1,
          lte: 2
        },
        stemming: true,
        weight: 1,
        fieldedSearch: false
      }
    }, done);
  };
  registerFile = function(done) {
    return exports.registerIndexDefinition('file', {
      name: {
        nGramLength: 1,
        stemming: true,
        weight: 1,
        fieldedSearch: false
      }
    }, done);
  };
  registerFolder = function(done) {
    return exports.registerIndexDefinition('folder', {
      name: {
        nGramLength: 1,
        stemming: true,
        weight: 1,
        fieldedSearch: false
      }
    }, done);
  };
  actions = [];
  if (!indexdefinitions.note) {
    actions.push(registerNote);
  }
  if (!indexdefinitions.file) {
    actions.push(registerFile);
  }
  if (!indexdefinitions.folder) {
    actions.push(registerFolder);
  }
  return async.series(actions, function(err) {
    return callback(err);
  });
};


/**
 * [TMP] Wait for a given document to be indexed
 *
 * Used in the former /data/index route
 * so apps tests wont break
 *
 */

exports.waitIndexing = function(id, callback) {
  var doc, docs, foundWaiting, i, len, tryAgain, type;
  foundWaiting = false;
  for (type in indexQueue) {
    docs = indexQueue[type];
    for (i = 0, len = docs.length; i < len; i++) {
      doc = docs[i];
      if (doc._id === id) {
        foundWaiting = true;
      }
    }
  }
  if (foundWaiting) {
    tryAgain = exports.waitIndexing.bind(null, id, callback);
    return setTimeout(tryAgain, 100);
  } else {
    return callback(null);
  }
};
