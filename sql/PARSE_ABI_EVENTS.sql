CREATE OR REPLACE FUNCTION `abi_functions`.PARSE_ABI_EVENTS(abi STRING) RETURNS ARRAY<STRUCT<name STRING, signature STRING, anonymous BOOL, `hash` STRING, inputs ARRAY<STRUCT<name STRING, type STRING, indexed BOOL>>>> LANGUAGE js AS """
  abi = JSON.parse(abi);
  res = [];
  abi.forEach(function(x){
    tuple = [];
    tuple['name'] = x.name;
    tuple['anonymous'] = x.anonymous;
 
    if (x.type != 'event') {
      return;
    }
    
    argtypes = [];
    argpairs = [];
    x.inputs.forEach(function(y){
      pair = [];
      pair['name'] = y.name;
      pair['type'] = y.type;
      pair['indexed'] = y.indexed;
      argpairs.push(pair);
      argtypes.push(y.type);
    });

    tuple['inputs'] = argpairs;
    tuple['signature'] = tuple['name'] + '(' + argtypes.join(',') + ')';
    tuple['hash'] = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(tuple['signature']));
    res.push(tuple);
  });
  return res;
"""
OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");
