// Generated by CoffeeScript 1.9.0
var Sharing;

Sharing = require('../lib/sharing');

module.exports.answerRequest = function(req, res, next) {
  var err;
  if (Object.keys(req.body).length === 0) {
    err = new Error('parameters missing');
    err.status = 400;
    return next(err);
  } else {
    return Sharing.targetAnswer(req, res, next);
  }
};
