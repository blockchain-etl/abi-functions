CREATE OR REPLACE FUNCTION `abi_functions`.PARSE_ABI_FUNCTIONS(abi STRING) RETURNS ARRAY<STRUCT<name STRING, signature STRING, constant BOOL, payable BOOL, method_id STRING, `hash` STRING, inputs ARRAY<STRUCT<name STRING, type STRING, indexed BOOL>>, outputs ARRAY<STRUCT<name STRING, type STRING>>>> LANGUAGE js AS """
  abi = JSON.parse(abi);
  res = [];
  abi.forEach(function(x){
    tuple = [];
    tuple['name'] = x.name;
    tuple['constant'] = x.constant;
    tuple['payable'] = x.payable;

    if (x.type != 'function') {
      return;
    }

    argtypes = [];
    
    argpairs = [];
    x.inputs.forEach(function(y){
      pair = [];
      pair['name'] = y.name;
      pair['type'] = y.type;
      argpairs.push(pair);
      argtypes.push(y.type);
    });

    outpairs = [];
    if (x.outputs) {
      x.outputs.forEach(function(y){
        pair = [];
        pair['name'] = y.name;
        pair['type'] = y.type;
        outpairs.push(pair);
      });
    }

    tuple['inputs'] = argpairs;
    tuple['outputs'] = outpairs;
    tuple['signature'] = tuple['name'] + '(' + argtypes.join(',') + ')';
    tuple['hash'] = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(tuple['signature']));
    tuple['method_id'] = tuple['hash'].substr(0,10);
    res.push(tuple);
  });
  return res;
"""
OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");
