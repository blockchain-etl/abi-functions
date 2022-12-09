# abi-functions

Utility functions for using an ABI to decode EVM calls and events.

## Examples

### Example 1

Assuming you have the ABI in a table mapping contract to address, this will return a table of all bids to buy CryptoPunks:

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

### Example 2

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

## Functions in this repo

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

### [PARSE_CALL](sql/PARSE_CALL.sql)

This function parses `transaction.input` in the context of an ABI to produce key/value pairs. Here's an example using the ENS ReverseRegistrar contract:

```sql
SELECT `abi_functions`.PARSE_CALL(ABI,input)
FROM
  `bigquery-public-data.crypto_ethereum.transactions` AS tx
WHERE tx.to_address = '0x084b1c3c81545d370f3634392de611caabff8148'
  --filter to method `claimWithResolver(address,address)`
  AND tx.input LIKE '0x0f5a5466%'
  AND tx.receipt_status = 1
```

### [PARSE_EVENT](sql/PARSE_EVENT.sql)

This function parses `logs.topics` and `logs.data` in the context of an ABI to produce key/value pairs. Here's an example extracting `PunkBidEntered` events from calls to the CryptoPunksMarket contract:

```sql
SELECT CryptoPunksMarket_evt_PunkBidEntered(`etherscan`.PARSE_EVENT(ABI,'PunkBidEntered',lg.topics,lg.data)).*
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

