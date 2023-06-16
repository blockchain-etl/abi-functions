CREATE OR REPLACE FUNCTION `substrate-etl.abi_functions.PARSE_CALL`(data STRING) 
RETURNS ARRAY<STRUCT<name STRING, value STRING>> 
LANGUAGE js AS 
"""
function convertBN(val) {
    if (Array.isArray(val)) {
        for (let i = 0; i < val.length; i++) {
            val[i] = convertBN(val[i])
	}
    } else if ( val._isBigNumber ) {
	return val.toString();
    } 
    return val;
}

try {
  let abiencoded = cn_calls[data.substring(0,10)];
  if ( abiencoded ) {
    let pieces = abiencoded.split("|");
    if ( pieces.length >= 3 ) {
      let functionName = pieces[0];
      // "stateMutability":"nonpayable"
      let abi = {"name":functionName, "type":"function","inputs":[], "outputs":[], "stateMutability":"nonpayable"};
      let flds = pieces[1].length > 0 ? pieces[1].split(",") : [];
      let types_unindexed = pieces[2].length > 0 ? pieces[2].split(",") : [];
      for (let idx = 0; idx < flds.length; idx++) { 
 	abi.inputs.push({name: flds[idx], type: types_unindexed[idx] });
      }
      const iface = new ethers.utils.Interface([abi]);
      const decodedData = iface.parseTransaction({ data });
      return(abi.inputs.map(function(y, idx) {
        let v = decodedData.args[idx];
        return({name: y.name, value: convertBN(v) });
      }));
    }
  }
} catch (err) {
    return [{name: "err", value: `${err.toString()}`}];
}
return null;
"""
OPTIONS(
  library = ["gs://cdn.polkaholic.io/pako.min.js", "gs://cdn.polkaholic.io/colorfulnotion-decoderData.js", "gs://blockchain-etl-bigquery/ethers-v5.js"]
);


