(ns sync-tests.sync-to-user
  (:require [clojure.edn :as edn]
            [clojure.java.io :as io]
            [jsonista.core :as j]
            [sync-tests.api :as api]
            [sync-tests.utils :as u]
            [clojure.core.async :as async]))

(def ^:private users
  (-> "sync_to_user.edn"
      io/resource
      slurp
      edn/read-string
      :users))

(def ^:private resources
  {:facilities "/api/v3/facilities/sync"
   :protocols "/api/v3/protocols/sync"
   :patients "/api/v3/patients/sync"
   :medical_histories "/api/v3/medical_histories/sync"
   :appointments "/api/v3/blood_pressures/sync"
   :blood_sugars "/api/v4/blood_sugars/sync"
   :blood_pressures "/api/v3/blood_pressures/sync"
   :precription_drugs "/api/v3/prescription_drugs/sync"})

(def ^:private limit 500)

(defn headers [{:keys [id facility-id access-token sync-region-id] :as user}]
  {"X-FACILITY-ID" facility-id
   "X-USER-ID"     id
   "Authorization" (apply str ["Bearer" " " access-token])})

(defn init-req-options [user]
  {:headers      (headers user)
   :query-params {:limit limit :process_token nil}})

(defn resource-sync
  ([resource user]
   (loop [options (init-req-options user)
          result  {resource {:total-elapsed-ms 0.0, :per-req-info: [] :record-count 0}}]
     (let [resource-path                    (get resources resource)
           {:keys [response start elapsed]} (u/timing #(deref (api/request resource-path options)))
           body                             (j/read-value (:body response))
           records                          (get body (name resource))
           response-process-token           (get body "process_token")
           updated-result                   (-> result
                                                (update-in [resource :record-count] + (count records))
                                                (update-in [resource :per-req-info] conj {:elapsed elapsed :start start})
                                                (update-in [resource :total-elapsed-ms] + elapsed))]
       (if (< (count records) limit)
         updated-result
         (recur (assoc-in options
                          [:query-params :process_token]
                          response-process-token)
                updated-result))))))

(defn resources-sync [user]
  (doall (map #(resource-sync %1 user) (keys resources))))

(defn across-users []
  (let [result-chan (async/chan (count users))]
    (mapv #(async/go (async/>! result-chan
                               (resources-sync %))) users)
    (async/<!! result-chan)))
