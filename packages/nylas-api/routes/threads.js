const Joi = require('joi');
const Serialization = require('../serialization');
const {createSyncbackRequest} = require('../route-helpers')

module.exports = (server) => {
  server.route({
    method: 'GET',
    path: '/threads',
    config: {
      description: 'Returns threads',
      notes: 'Notes go here',
      tags: ['threads'],
      validate: {
        params: {
        },
      },
      response: {
        schema: Joi.array().items(
          Serialization.jsonSchema('Thread')
        ),
      },
    },
    handler: (request, reply) => {
      request.getAccountDatabase().then((db) => {
        const {Thread} = db;
        Thread.findAll({limit: 50}).then((threads) => {
          reply(Serialization.jsonStringify(threads));
        })
      })
    },
  });

  server.route({
    method: 'PUT',
    path: '/threads/${id}',
    config: {
      description: 'Update a thread',
      notes: 'Can move between folders',
      tags: ['threads'],
      validate: {
        params: {
          payload: {
            folder_id: Joi.string(),
          },
        },
      },
      response: {
        schema: Joi.array().items(
          Serialization.jsonSchema('Thread')
        ),
      },
    },
    handler: (request, reply) => {
      createSyncbackRequest(request, reply, {
        type: "MoveToFolder",
        props: {
          folderId: request.params.folder_id,
          threadId: requres.params.id,
        }
      })
    },
  });
};
