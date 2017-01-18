import request from 'request-promise';
import {DatabaseConnector} from 'cloud-core';

let db = null // cache this.

/**
 * This is the validateFunc for https://github.com/hapijs/hapi-auth-basic
 *
 * API requests are of the form:
 * https://username:pass@n1.nylas.com/some/route
 *
 * The username field is the AccountToken of the N1 Cloud Account (aka
 * email account)
 * The password field is the N1 Identity Token.
 *
 * Then cb callback param must be called with the signature of:
 * function(err, isValid, credentials)
 */
export async function apiAuthenticate(req, username, password, cb) {
  const accountToken = username
  const n1IdentityToken = password
  if (!db) { db = await DatabaseConnector.forShared() }

  const token = await db.AccountToken.find({where: {value: accountToken}})
  if (!token) return cb(null, false, {});

  const account = await token.getAccount();
  account.n1IdentityToken = n1IdentityToken;

  let identPath = "billing.nylas.com";
  if (process.env.NODE_ENV === "staging") {
    identPath = "billing-staging.nylas.com"
  }

  try {
    const identity = await request(`https://${identPath}/n1/user`, {
      auth: {username: n1IdentityToken, password: ''},
    })
    global.Logger.info(identity, `Got ${identPath} identity response`)
    return cb(null, true, {account, identity});
  } catch (err) {
    return cb(err, false, {})
  }
}
