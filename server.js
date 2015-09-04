var application;

application = module.exports = function(callback) {
  var americano, db, errorMiddleware, initialize, plugdb;
  americano = require('americano');
  initialize = require('./server/initialize');
  errorMiddleware = require('./server/middlewares/errors');
  plugdb = require('./server/lib/plug');
  db = require('./server/lib/db');
  return db(function() {
    var exitHandler, options;
    options = {
      name: 'data-system',
      port: process.env.PORT || 9101,
      host: process.env.HOST || "127.0.0.1",
      root: __dirname
    };
    americano.start(options, function(app, server) {
      app.use(errorMiddleware);
      return initialize(app, server, callback);
    });
    process.stdin.resume();
    exitHandler = function(options, err) {
      if (options.cleanup) {
        console.log('clean');
      }
      if (err) {
        console.log(err.stack);
      }
      console.log('is init : ' + plugdb.isInit());
      if (plugdb.isInit() && options.exit) {
        return plugdb.close(function(err) {
          if (!err) {
            console.log('PlugDB closed');
          }
          return process.exit();
        });
      }
    };
    process.on('exit', exitHandler.bind(null, {
      cleanup: true
    }));
    process.on('SIGINT', exitHandler.bind(null, {
      exit: true
    }));
    return process.on('uncaughtException', exitHandler.bind(null, {
      exit: true
    }));
  });
};

if (!module.parent) {
  application();
}
