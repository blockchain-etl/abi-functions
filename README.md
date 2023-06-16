# abi-functions

This repo contains BigQuery UDFs to decode EVM calls and events **without knowing an ABI** using 2 key functions:

* `abi_functions.PARSE_CALL(input)`
* `abi_functions.PARSE_EVENT(data, topics)`

To support ABI-less decoding, each of the above function uses a large
1MB library containing 2 compressed maps, one covering known call
methods and known event topics.  Using the call 4byte methodID or the
event's topic[0], the most likely ABI is synthesized from the map and
decoding is attempted.  For events, given the number of topics
observed and the ABI guess, any mismatch results in combinatorial
search on all possible indexed combinations, with the first success
considered valid.


### How It Works:
* Big Picture: approach taken in `PARSE_CALL` and `PARSE_EVENT` is to build a 1MB library of 2 _compressed_ maps: `call_map` and `event_map`
* A `signatures` table is compiled by aggregating ABI signatures with 2.8MM+ records from multiple open-source repos.  However most of these hex signatures have never been observed on chain.
* So, we tally _actual_ observations (`numObservations` from `logs` and `transactions`) and presence in ABI contracts (`numContracts` from `contracts`)
in `crypto_ethereum.{` EVM Chains to build a reduced dataset
* The current size of this reduced dataset with known ABIs is:

```
+-----------------------+--------------+----------+
| length(hex_signature) | abiAvailable | count(*) |
+-----------------------+--------------+----------+
|                    10 |        20147 |    63600 |
|                    66 |        11008 |    11008 |
+-----------------------+--------------+----------+
```

* To maximize decoding rates, we actually only include records with 2+ or more observations in 2023 to fit in a single 1MB map. Potentially the maps could be split into 2 files and increase coverage a bit further.

### Plan:

This repo is a work in progress

* Measure decoding rates and time to decode a day.  

* Rebuild underlying map with GitHub Actions on a weekly basis.  We will update the `abi_functions` dataset weekly to support new call methods and new topics.

* Support EVM chain-specific libraries and EVM ecosystem wide libraries.

## Key Decoding User-defined Functions, with Examples

### [PARSE_CALL](sql/PARSE_CALL.sql)

This function parses `transaction.input` *without* an ABI to produce key/value pairs decoding the input:

Usage: (single record)
```sql
select `substrate-etl.abi_functions.PARSE_CALL`("0xe343fe12000000000000000000000000bd402a0cf18148389c6f10b6e67aea915c3960ec000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000258f474786ddfd37abce6df6bbb1dd5dfc4434a0000000000000000000000000000000000000000000000000ed8db3e1827446c00000000000000000000000000000000000000000000000000000032bfdfa8d0") as call_args
```
returns

```
[{
  "call_args": [{
    "name": "fromToken",
    "value": "0xbd402A0cf18148389c6f10b6e67aea915C3960ec"
  }, {
    "name": "toToken",
    "value": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  }, {
    "name": "recipient",
    "value": "0x0258F474786DdFd37ABCE6df6BBb1Dd5dfC4434a"
  }, {
    "name": "shareToMin",
    "value": "1069845971240174700"
  }, {
    "name": "shareFrom",
    "value": "217967470800"
  }]
}]
```

This can be used on _arbitrary_ inputs in bulk processing with _varying_ calls / ABIs:

Usage: (bulk processing)
```
SELECT
  `hash`,
  LEFT(input, 10) AS methodID,
  input,
  `substrate-etl.abi_functions.PARSE_CALL`(input) 
FROM
  `bigquery-public-data.crypto_ethereum.transactions` AS transactions
WHERE
  DATE(block_timestamp) = "2023-06-01" and length(input) >= 10
  limit 2000;
```

This can be used on _arbitrary_ inputs in bulk call processing with the same ABI as well:

Usage: (bulk processing)
```sql
SELECT `substrate-etl.abi_functions`.PARSE_CALL(input)
FROM
  `bigquery-public-data.crypto_ethereum.transactions` AS tx
WHERE tx.to_address = '0x084b1c3c81545d370f3634392de611caabff8148'
  --filter to method `claimWithResolver(address,address)`
  AND tx.input LIKE '0x0f5a5466%'
  AND tx.receipt_status = 1
```

### [PARSE_EVENT](sql/PARSE_EVENT.sql)

This function parses `logs.topics` and `logs.data` **without an ABI** to produce key/value pairs. 

* `PARSE_EVENT(data, topics)`

Usage: (single record)
```
select `substrate-etl.abi_functions.PARSE_EVENT`("0x00000000000000000000000000000000000000000000000000036cc84b90729200000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000002000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000323012d0a49fbd86dd1c4d363c7ea63244852e21", ["0x6fd378a9d8b7345c2e5b18229aaf1e39d32b177b501d0a0d26a0a858a23a9624"]) as events
```

returns:
```json
[{
  "events": [{
    "name": "from",
    "value": "0x40CB4DA705a044016e66dB2E30AdE93EbFe4abD4"
  }, {
    "name": "to",
    "value": "0x9A44630bD49001645291f2A08F4F07eB04bC184a"
  }, {
    "name": "value",
    "value": "50000000000000000000"
  }]
}]
```

This can be used for bulk processing events with _varying_ ABIs:

Usage: (bulk processing of 500 records of a day)
```
SELECT
  transaction_hash,
  DATA,
  topics,
  `substrate-etl.abi_functions.PARSE_EVENT`(data, topics) AS events
FROM
  `bigquery-public-data.crypto_ethereum.logs` AS logs
WHERE
  DATE(block_timestamp) = "2023-06-01"
LIMIT
  500;
```

Usage: (bulk processing of `PunkBidEntered` events from calls to the `CryptoPunksMarket` contract:

```sql
SELECT CryptoPunksMarket_evt_PunkBidEntered(`etherscan`.PARSE_EVENT(lg.data,lg.topics)).*
FROM
  `bigquery-public-data.crypto_ethereum.transactions` AS tx
  ,`bigquery-public-data.crypto_ethereum.logs` AS lg
WHERE TRUE
  AND tx.to_address = '0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb'
  AND lg.address = tx.to_address
  AND ARRAY_LENGTH(lg.topics) > 0 
  --this is the keccak256 hash of `PunkBidEntered(uint256,uint256,address)` from the ABI
  AND lg.topics[OFFSET(0)] = '0x5b859394fabae0c1ba88baffe67e751ab5248d2e879028b8c8d6897b0519f56a' 
  AND tx.hash = lg.transaction_hash
  AND tx.receipt_status = 1
```

### [GENERATE_ABI_FUNCTIONS](sql/GENERATE_ABI_FUNCTIONS.sql)

Calling this function with a name prefix and an ABI will return two arrays of `CREATE FUNCTION` statements that can be used with a contract that implements the ABI.
- an array for processing method calls (parses `transactions.input`)
- an array for processing log events (parses `logs.topics`)

Consider the [ABI](abi/CryptoPunksMarket.abi) for the `CryptoPunksMarket` contract at [`0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb`](https://etherscan.io/address/0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb).

We can invoke the code generator as:

```sql
SELECT `abi_functions`.GENERATE_ABI_FUNCTIONS("CryptoPunksMarket",ABI)
```

This produces a number of statments, for example this one for processing calls to the contract's `name()` function:

```sql
CREATE TEMP FUNCTION CryptoPunksMarket_call_name(kv ARRAY<STRUCT<arg STRING,val STRING>>) RETURNS STRUCT<> LANGUAGE js AS """
want=new Set([]);res=[];kv.forEach(function(el){if(want.has(el.arg)){res[el.arg]=el.val}});return res;
"""
OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");
```

and this one for processing `Assign` event logs

```sql
CREATE TEMP FUNCTION CryptoPunksMarket_evt_Assign(kv ARRAY<STRUCT<arg STRING,val STRING>>) RETURNS STRUCT<to STRING,punkIndex STRING> LANGUAGE js AS """
want=new Set(['to','punkIndex']);res=[];kv.forEach(function(el){if(want.has(el.arg)){res[el.arg]=el.val}});return res;
"""
OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");
```

Note that each of these requires an array of key/value pairs, `kv ARRAY<STRUCT<arg STRING,val STRING>>`.


#### Example 1

Assuming you have the [ABI](https://github.com/blockchain-etl/abi-functions/blob/main/abi/CryptoPunksMarket.abi) in a table mapping contract to address, this will return a table of all bids to buy CryptoPunks:

```sql
CREATE TEMP FUNCTION CryptoPunksMarket_evt_PunkBidEntered(kv ARRAY<STRUCT<arg STRING,val STRING>>) RETURNS STRUCT<punkIndex STRING,value STRING,fromAddress STRING> LANGUAGE js AS """
want=new Set(['punkIndex','value','fromAddress']);res=[];kv.forEach(function(el){if(want.has(el.arg)){res[el.arg]=el.val}});return res;
"""
OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");

WITH CryptoPunksMarket_evt_PunkBidEntered AS (
  SELECT CryptoPunksMarket_evt_PunkBidEntered(`etherscan`.PARSE_EVENT(abi,'PunkBidEntered',lg.topics,lg.data)).*
  FROM
    `bigquery-public-data.crypto_ethereum.transactions` AS tx
    ,`bigquery-public-data.crypto_ethereum.logs` AS lg
    ,`dataset.contract_abis` AS ab
    WHERE TRUE
      --this is the known contract address
      AND tx.to_address = '0xb47e3cd837ddf8e4c57f05d70ab865de6e193bbb'
      AND lg.address = tx.to_address
      AND ARRAY_LENGTH(lg.topics) > 0 
      --this is the keccak256 hash of `PunkBidEntered(uint256,uint256,address)` from the ABI
      AND lg.topics[OFFSET(0)] = '0x5b859394fabae0c1ba88baffe67e751ab5248d2e879028b8c8d6897b0519f56a'
    AND tx.hash = lg.transaction_hash
    AND tx.receipt_status = 1
    AND ab.address = tx.to_address
)
SELECT * FROM CryptoPunksMarket_evt_PunkBidEntered
```

Generating a result like:

| punkIndex | value                | fromAddress                                 |
|----------:|---------------------:|---------------------------------------------|
|     9999  |     5000000000000000 | 0x664e23e4a17a4c7da26c706be5a861c0f7ff569d  |
|      728  |        5000000000000 | 0x664e23e4a17a4c7da26c706be5a861c0f7ff569d  |
|     2207  | 48500000000000000000 | 0x1919db36ca2fa2e15f9000fd9cdc2edcf863e685  |

#### Example 2

```sql
CREATE TEMP FUNCTION parse_ReverseRegistrar_call_claimWithResolver(kv ARRAY<STRUCT<arg STRING,val STRING>>) RETURNS STRUCT<owner STRING,resolver STRING> LANGUAGE js AS """want=new Set(['owner','resolver']);res=[];kv.forEach(function(el){if(want.has(el.arg)){res[el.arg]=el.val}});return res;""" OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");

WITH ReverseRegistrar_call_claimWithResolver AS (
  SELECT parse_ReverseRegistrar_call_claimWithResolver(`abi_functions`.PARSE_CALL(abi,input)).*
  FROM
    `bigquery-public-data.crypto_ethereum.transactions` AS tx
    ,`dataset.contract_abis` AS ab
  WHERE tx.to_address = '0x084b1c3c81545d370f3634392de611caabff8148'
  AND tx.input LIKE '0x0f5a5466%'
    AND tx.receipt_status = 1
    AND ab.address = tx.to_address
)

SELECT * FROM ReverseRegistrar_call_claimWithResolver
```

Generating a result like:

| arg      | val                                          |
| ---------|----------------------------------------------|
| owner    | `0x0000000000000000000000000000000000000000` |
| resolver | `0xf58d55f06bb92f083e78bb5063a2dd3544f9b6a3` |
| owner    | `0xe11d762cc7b0448ed8c565734b742ce39bbb38a6` |
| resolver | `0x0465719485db64e24d73d1619e03950830e4a5b3` |

