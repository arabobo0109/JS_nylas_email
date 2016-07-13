const {JSONType} = require('../../database-types');

module.exports = (sequelize, Sequelize) => {
  const Folder = sequelize.define('folder', {
    accountId: { type: Sequelize.STRING, allowNull: false },
    version: Sequelize.INTEGER,
    name: Sequelize.STRING,
    role: Sequelize.STRING,
    syncState: JSONType('syncState'),
  }, {
    charset: 'utf8',
    classMethods: {
      associate: ({Message, Thread}) => {
        Folder.hasMany(Message)
        Folder.belongsToMany(Thread, {through: 'thread_folders'})
      },
    },
    instanceMethods: {
      toJSON: function toJSON() {
        return {
          id: this.id,
          account_id: this.accountId,
          object: 'folder',
          name: this.role,
          display_name: this.name,
        };
      },
    },
  });

  return Folder;
};
