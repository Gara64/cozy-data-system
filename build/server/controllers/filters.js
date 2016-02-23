// Generated by CoffeeScript 1.10.0
var checkToken, errors,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

checkToken = require('../lib/token').checkToken;

errors = require('../middlewares/errors');

module.exports.checkDevice = function(req, res, next) {
  var auth, err, isAuthenticated, name, ref;
  auth = req.header('authorization');
  ref = checkToken(auth), err = ref[0], isAuthenticated = ref[1], name = ref[2];
  if (err || !isAuthenticated || !name) {
    return next(errors.notAuthorized());
  } else {
    req.params.id = "_design/filter-" + name + "-" + req.params.id;
    return next();
  }
};

module.exports.fixBody = function(req, res, next) {
  if (indexOf.call(req.body, "views") < 0) {
    req.body.views = {};
  }
  return next();
};
