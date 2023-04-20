CREATE OR REPLACE FUNCTION `blocktrekker.udfs.PARSE_ABI_FUNCTIONS`(abi STRING, dune_name STRING) RETURNS ARRAY<STRUCT<name STRING, hash_id STRING, constant BOOL, payable BOOL, inputs STRING, outputs STRING>> LANGUAGE js
OPTIONS (library=["gs://blockchain-etl-bigquery/ethers.js"]) AS R"""
abi = JSON.parse(abi);
  res = [];
  const typeMap = {
    "uint32[]": "INT64",
    "uint16[]": "INT64",
    "uint8[]": "INT64",
    "uint64[]": "INT64",
    "uint128[]": "INT64",
    "uint256[]": "BIGNUMERIC",
    "bool[]": "BOOL",
    "address[]": "STRING",
    "string[]": "STRING",
    "bytes[]": "BYTES",
    "bytes4": "BYTES",
    "bytes32": "BYTES",
    "uint32": "INT64",
    "uint16": "INT64",
    "uint8": "INT64",
    "uint64": "INT64",
    "unit80": "INT64",
    "uint112": "INT64",
    "uint128": "INT64",
    "uint168": "BIGNUMERIC",
    "uint256": "BIGNUMERIC",
    "BIGNUMERIC": "BIGNUMERIC",
    "bool": "BOOL",
    "address": "STRING",
    "STRING": "STRING",
    "string": "STRING",
    "bytes": "BYTES"
  };


  const nameMap = {
    "from": "from_address",
    "to": "to_address",
    "limit": "_limit",
    "all": "_all"
  };
  
  abi.forEach(function(x){
    tuple = [];
    tuple['constant'] = x.constant;
    tuple['payable'] = x.payable;
    if (x.type != 'function') {
      return;
    }

    argtypes = [];
    argpairs = [];
    let count = 1;
    x.inputs.forEach(function(y){
      pair = {};
      argtypes.push(y.type);
      if (y.name in nameMap) {
        pair.name = nameMap[y.name];
      } else if (y.name == "") {
        pair.name = `input_${count}`;
      } else {
        pair.name = y.name ? y.name : `input_${count}`;
      }
      if (y.type in typeMap) {
        pair.type = typeMap[y.type];
      } else {
        if (y.type.slice(0, 4).toLowerCase() === "uint") {
          pair.type = "BIGNUMERIC";
        } else {
          pair.type = "STRING";
        }
      }
      argpairs.push(JSON.stringify(pair));
      count = count + 1;
    });

    outpairs = [];
    if (x.outputs) {
      let count = 1;
      x.outputs.forEach(function(y){
        pair = {};
        if (y.name in nameMap) {
          pair.name = nameMap[y.name];
        } else if (y.name == "") {
          pair.name = `output_${count}`
        } else {
          pair.name = y.name ? y.name : `output_${count}`;
        }
        if (y.type in typeMap) {
          pair.type = typeMap[y.type];
        } else if (y.type.slice(0, 4).toLowerCase() === "uint") {
          pair.type = "BIGNUMERIC";
        } else {
          pair.type = "STRING";
        }
          outpairs.push(JSON.stringify(pair));
      });
    }
    tuple['inputs'] = argpairs.join(",");
    tuple['outputs'] = outpairs.join(",");
    tuple['hash_id'] = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(x.name + '(' + argtypes.join(',') + ')')).substr(0,10);
    tuple['name'] = dune_name + "_call_" + x.name;
    res.push(tuple);
  });
  return res;
""";
