const Joi = require('joi');
const {DatabaseConnector, PubsubConnector} = require(`cloud-core`);
const {DeltaStreamBuilder} = require('isomorphic-core')

module.exports = (server) => {
  server.route({
    method: 'GET',
    path: '/delta/streaming',
    config: {
      validate: {
        query: {
          cursor: Joi.string().required(),
        },
      },
    },
    handler: (request, reply) => {
      const {account} = request.auth.credentials;

      DeltaStreamBuilder.buildStream(request, {
        accountId: account.id,
        cursor: request.query.cursor,
        databasePromise: DatabaseConnector.forShared(),
        deltasSource: PubsubConnector.observeDeltas(account.id),
      }).then((stream) => {
        reply(stream)
      });
    },
  });

  server.route({
    method: 'POST',
    path: '/delta/latest_cursor',
    handler: (request, reply) => {
      DeltaStreamBuilder.buildCursor({
        databasePromise: DatabaseConnector.forShared(),
      }).then((cursor) => {
        reply({cursor})
      });
    },
  });
};
