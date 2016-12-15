import Actions from './actions'
import NylasAPIRequest from './nylas-api-request'
import {APIError} from './errors'


/**
 * This API request is meant to be used for requests that create a
 * SyncbackRequest inside K2.
 * When the initial http request succeeds, this means that the task was created,
 * but we cant tell if the task actually succeeded or failed until some time in
 * the future when its processed inside K2's sync loop.
 *
 * A SyncbackTaskAPIRequest will only resolve until the underlying K2 syncback
 * request has actually succeeded, or reject when it fails, by listening to
 * deltas for ProviderSyncbackRequests
 */
class SyncbackTaskAPIRequest {

  constructor({api, options}) {
    options.returnsModel = true
    this._request = new NylasAPIRequest({api, options})
    this._onSyncbackRequestCreated = options.onSyncbackRequestCreated || (() => {})
  }

  run() {
    return new Promise(async (resolve, reject) => {
      try {
        const syncbackRequest = await this._request.run()
        await this._onSyncbackRequestCreated(syncbackRequest)
        const syncbackRequestId = syncbackRequest.id
        const unsubscribe = Actions.didReceiveSyncbackRequestDeltas
        .listen((syncbackRequests) => {
          const failed = syncbackRequests.find(r => r.id === syncbackRequestId && r.status === 'FAILED')
          const succeeded = syncbackRequests.find(r => r.id === syncbackRequestId && r.status === 'SUCCEEDED')
          if (failed) {
            unsubscribe()
            const error = new APIError({
              error: failed.error,
              body: failed.error.message,
              statusCode: failed.error.statusCode,
            })
            reject(error)
          } else if (succeeded) {
            unsubscribe()
            resolve(succeeded.responseJSON || {})
          }
        })
      } catch (err) {
        reject(err)
      }
    })
  }
}

export default SyncbackTaskAPIRequest
