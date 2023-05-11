CREATE OR REPLACE FUNCTION `blocktrekker.udfs.PARSE_ABI_EVENTS`(abi STRING, dune_name STRING) RETURNS ARRAY<STRUCT<name STRING, anonymous BOOL, hash_id STRING, inputs STRING, types STRING>> LANGUAGE js
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
    tuple['name'] = dune_name + "_evt_" + x.name;
    tuple['orig_name'] = x.name;
    tuple['anonymous'] = x.anonymous;

    if (x.type != 'event') {
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
    tuple['inputs'] = argpairs.join(",");
    tuple['hash_id'] = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(tuple['orig_name'] + '(' + argtypes.join(',') + ')'));
    res.push(tuple);
  });
  return res;
""";
