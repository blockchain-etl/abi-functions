CREATE OR REPLACE FUNCTION `abi_functions`.PARSE_CALL(abi STRING, dat STRING) RETURNS ARRAY<STRUCT<arg STRING, val STRING>> LANGUAGE js AS """
  abi = JSON.parse(abi);
  var interface_instance = new ethers.utils.Interface(abi);
  txargs = [];
  txtypes = [];
  res = [];

  // try-catch - input may be malformed.
  try {
    var pt = interface_instance.parseTransaction({data: dat});

    frag = "";
    abi.forEach(function(x){
      if (x.name == pt.name) {
        frag = x;
      }
    });
    txvals = pt.args;
    //txtypes[pt.name]
    frag.inputs.forEach(function(x) {
      txargs.push(x.name);
      txtypes.push(x.type);
    });
    for (i = 0; i < txvals.length; i++) {
      val = txvals[i];
      if (txtypes[i] == 'address') {
        val = val.toLowerCase();

      }
      res.push({arg:txargs[i],val:val});
    }
  } catch(e) {}
  return res;
"""
OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");
