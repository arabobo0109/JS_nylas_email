const _ = require('underscore')

module.exports = (db, sequelize, {only, onCreatedTransaction} = {}) => {
  if (!db.Transaction) {
    throw new Error("Cannot enable transaction logging, there is no Transaction model class in this database.")
  }
  const isTransaction = ($modelOptions) => {
    return $modelOptions.name.singular === "transaction"
  }

  const allIgnoredFields = (changedFields) => {
    return _.isEqual(changedFields, ['updatedAt', 'version'])
  }

  const transactionLogger = (event) => {
    return ({dataValues, _changed, $modelOptions}) => {
      let name = $modelOptions.name.singular;
      if (name === 'metadatum') {
        name = 'metadata';
      }

      if (only && !only.includes(name)) {
        return;
      }

      const changedFields = Object.keys(_changed)
      if ((isTransaction($modelOptions) || changedFields.length === 0 || allIgnoredFields(changedFields))) {
        return;
      }

      const accountId = db.accountId ? db.accountId : dataValues.accountId;
      if (!accountId) {
        throw new Error("Assertion failure: Cannot create a transaction - could not resolve accountId.")
      }

      const transactionData = Object.assign({event}, {
        object: name,
        objectId: dataValues.id,
        accountId: accountId,
        changedFields: changedFields,
      });

      db.Transaction.create(transactionData).then(onCreatedTransaction)
    }
  }

  sequelize.addHook("afterCreate", transactionLogger("create"))
  sequelize.addHook("afterUpdate", transactionLogger("modify"))

  // NOTE: Hooking UPSERT requires Sequelize 4.x. We're
  // on version 3 right now, but leaving this here for when we upgrade.
  sequelize.addHook("afterUpsert", transactionLogger("modify"))
  sequelize.addHook("afterDelete", transactionLogger("delete"))
}
