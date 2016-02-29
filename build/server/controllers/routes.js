// Generated by CoffeeScript 1.10.0
var access, account, attachments, binaries, data, filters, indexer, mails, replication, requests, sharing, user, utils;

data = require('./data');

requests = require('./requests');

attachments = require('./attachments');

binaries = require('./binaries');

indexer = require('./indexer');

mails = require('./mails');

user = require('./user');

account = require('./accounts');

access = require('./access');

replication = require('./replication');

sharing = require('./sharing');

filters = require('./filters');

utils = require('../middlewares/utils');

module.exports = {
  '': {
    get: [data.index]
  },
  'data/': {
    post: [utils.checkPermissionsByBody, data.encryptPassword, data.create]
  },
  'data/search/': {
    post: [utils.checkPermissionsFactory('all'), indexer.search]
  },
  'data/:id/': {
    get: [utils.getDoc, utils.checkPermissionsByDoc, data.decryptPassword, data.find],
    post: [utils.checkPermissionsByBody, data.encryptPassword, data.create],
    put: [utils.lockRequest, utils.checkPermissionsByBody, utils.getDoc, data.encryptPassword, data.update, utils.unlockRequest],
    "delete": [utils.lockRequest, utils.getDoc, utils.checkPermissionsByDoc, data.softdelete, utils.unlockRequest]
  },
  'data/exist/:id/': {
    get: [data.exist]
  },
  'data/upsert/:id/': {
    put: [utils.lockRequest, utils.checkPermissionsByBody, data.encryptPassword, data.upsert, utils.unlockRequest]
  },
  'data/merge/:id/': {
    put: [utils.lockRequest, utils.checkPermissionsByBody, utils.getDoc, utils.checkPermissionsByDoc, data.encryptPassword, data.merge, utils.unlockRequest]
  },
  'request/:type/:req_name/': {
    post: [utils.checkPermissionsByType, requests.results],
    put: [utils.checkPermissionsByType, utils.lockRequest, requests.definition, utils.unlockRequest],
    "delete": [utils.checkPermissionsByType, utils.lockRequest, requests.remove, utils.unlockRequest]
  },
  'request/:type/:req_name/destroy/': {
    put: [utils.checkPermissionsByType, requests.removeResults]
  },
  'tags': {
    get: [requests.tags]
  },
  'doctypes': {
    get: [requests.doctypes]
  },
  'data/:id/attachments/': {
    post: [utils.lockRequest, utils.getDoc, utils.checkPermissionsByDoc, attachments.add, utils.unlockRequest]
  },
  'data/:id/attachments/:name': {
    get: [utils.getDoc, utils.checkPermissionsByDoc, attachments.get],
    "delete": [utils.lockRequest, utils.getDoc, utils.checkPermissionsByDoc, attachments.remove, utils.unlockRequest]
  },
  'data/:id/binaries/convert': {
    get: [utils.lockRequest, utils.getDoc, utils.checkPermissionsByDoc, binaries.convert, utils.unlockRequest]
  },
  'data/:id/binaries/': {
    post: [utils.lockRequest, utils.getDoc, utils.checkPermissionsByDoc, binaries.add, utils.unlockRequest]
  },
  'data/:id/binaries/:name': {
    get: [utils.getDoc, utils.checkPermissionsByDoc, binaries.get],
    "delete": [utils.lockRequest, utils.getDoc, utils.checkPermissionsByDoc, binaries.remove, utils.unlockRequest]
  },
  'access/': {
    post: [utils.checkPermissionsFactory('access'), access.create]
  },
  'access/:id/': {
    put: [utils.checkPermissionsFactory('access'), access.update],
    "delete": [utils.checkPermissionsFactory('access'), utils.lockRequest, utils.getDoc, access.remove, utils.unlockRequest]
  },
  'filters/:id': {
    get: [filters.checkDevice, utils.getDoc, data.find],
    post: [filters.checkDevice, filters.fixBody, data.create],
    put: [filters.checkDevice, filters.fixBody, utils.lockRequest, data.upsert, utils.unlockRequest],
    "delete": [filters.checkDevice, utils.lockRequest, utils.getDoc, data["delete"], utils.unlockRequest]
  },
  'replication/:id([^_]*)/:name*': {
    get: [utils.getDoc, utils.checkPermissionsByDoc, replication.proxy]
  },
  'replication/*': {
    post: [utils.checkPermissionsPostReplication, replication.proxy],
    get: [replication.proxy],
    put: [utils.checkPermissionsPutReplication, replication.proxy]
  },
  'data/index/clear-all/': {
    "delete": [utils.checkPermissionsFactory('all'), indexer.removeAll]
  },
  'data/index/status': {
    get: [indexer.indexingStatus]
  },
  'data/index/define/:type': {
    post: [utils.checkPermissionsByType, indexer.defineIndex]
  },
  'data/index/:id': {
    post: [indexer.index],
    "delete": [indexer.remove]
  },
  'data/search/:type': {
    post: [utils.checkPermissionsByType, indexer.search]
  },
  'mail/': {
    post: [utils.checkPermissionsFactory('send mail'), mails.send]
  },
  'mail/to-user': {
    post: [utils.checkPermissionsFactory('send mail to user'), mails.sendToUser]
  },
  'mail/from-user': {
    post: [utils.checkPermissionsFactory('send mail from user'), mails.sendFromUser]
  },
  'user/': {
    post: [utils.checkPermissionsFactory('User'), user.create]
  },
  'user/merge/:id': {
    put: [utils.lockRequest, utils.checkPermissionsFactory('User'), utils.getDoc, user.merge, utils.unlockRequest]
  },
  'accounts/password/': {
    post: [account.checkPermissions, account.initializeKeys],
    put: [account.checkPermissions, account.updateKeys]
  },
  'accounts/reset/': {
    "delete": [account.checkPermissions, account.resetKeys]
  },
  'accounts/': {
    "delete": [account.checkPermissions, account.deleteKeys]
  },
  'sharing/': {
    post: [sharing.create, sharing.requestTarget]
  },
  'sharing/sendAnswer': {
    post: [sharing.handleAnswer, sharing.sendAnswer]
  },
  'sharing/answer': {
    post: [sharing.validateTarget, sharing.replicate]
  }
};
