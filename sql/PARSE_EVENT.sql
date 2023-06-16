CREATE OR REPLACE FUNCTION `substrate-etl.abi_functions.PARSE_EVENT`(data STRING, topics ARRAY<STRING>) 
RETURNS ARRAY<STRUCT<name STRING, value STRING>> 
LANGUAGE js AS 
"""
function generateBinaryNumbers(N, k) {
  const result = [];
  function generateCombinations(n, k, prefix = '') {
    if (k === 0) {
      result.push(prefix.padStart(N, '0'));
      return;
    }
    if (n === 0) return;
    generateCombinations(n - 1, k - 1, '1' + prefix);
    generateCombinations(n - 1, k, '0'+ prefix);
  }
  generateCombinations(N, k);
  return result;
}
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

let abiCandidates = [];
try {
    let abi_maybe = null;
    let text_signature = null;
    let abiencoded = cn_events[topics[0].substring(0,10)];
    if ( abiencoded ) {
      let pieces = abiencoded.split("|");
      if ( pieces.length == 4 ) {
        let eventName = pieces[0];
        let abi = {"name":eventName,"type":"event","inputs":[], "outputs":[], "stateMutability":"nonpayable"};
        let flds = pieces[1].length > 0 ? pieces[1].split(",") : [];
        let types_unindexed = pieces[2].length > 0 ? pieces[2].split(",") : [];
        let types_indexed = pieces[3].length > 0 ? pieces[3].split(",") : [];
        let types = [];
        let u = 0;
        let i = 0;
        for (let idx = 0; idx < flds.length; idx++) {
           let f = flds[idx];
	   let lastchar = f.substring(f.length-1, f.length);
	   if ( lastchar == "*" ) {
	     abi.inputs.push({"indexed": true, name: f.substring(0, f.length-1), type: types_indexed[i] });
             types.push(types_indexed[i]);  
	     i++;
	   } else {
	     abi.inputs.push({"indexed": false, name: f, type: types_unindexed[u] });
             types.push(types_unindexed[u]);  
	     u++;
	   }
        }
        abi_maybe = JSON.stringify(abi);
        text_signature = `${eventName}(${types.join(",")})`
      }
    } else {
      return null;
    }
    let abiMaybe = JSON.parse(abi_maybe);
    let N = abiMaybe.inputs.length; 
    let topicLen = 0;
    abiMaybe.inputs.forEach(function(x) {
	if ( x.indexed ) topicLen++;
    });
    if ( topics.length != topicLen + 1 ) {
	if ( topics.length == 1 || topics.length == N + 1) { 
	    let v = topics.length == 1 ? false : true;
	    let cand = JSON.parse(abi_maybe);
	    for (let i = 0; i < N; i++) {
		cand.inputs[i].indexed = v;
	    }
	    abiCandidates.push(cand);
	} else if ( (topics.length == 2 || topics.length == N ) ){  
	    let v = ( topics.length == 2 ) ? true : false;
	    for ( let i = 0; i < N; i++) {
		let cand = JSON.parse(abi_maybe);
		for (let j = 0; j < N; j++) {
		    cand.inputs[j].indexed = ( i == j ) ? v : ! v;
		}
		abiCandidates.push(cand);
	    }
	} else { 
	    let binaryStrings = generateBinaryNumbers(N, topics.length - 1);
	    for ( const b of binaryStrings ) {
      		let cand = JSON.parse(abi_maybe);
		for (let j = 0; j < b.length; j++) {
		    cand.inputs[j].indexed = ( b[j] == "1" ) ? true : false;
		}
		abiCandidates.push(cand);
	    }
	}
	
    } else {
	abiCandidates.push(abiMaybe);
    }
    let tries = 0;
    for (const abiCandidate of abiCandidates) {
	try {
	    const iface = new ethers.utils.Interface([abiCandidate]);
	    const decodedData = iface.decodeEventLog(ethers.utils.id(text_signature), data, topics);
	    let res = abiCandidate.inputs.map(function(y, idx){
		let v = decodedData[idx];
		return({name: y.name, value: convertBN(v) });
	    });
	    if ( tries > 0 ) {
		res.push({"name": "tries", "value": tries});
	    }
	    return res;
	} catch ( err ) {
	    tries++;
	}
    }
} catch (err) {
    return [{name: "err", value: `${err.toString()}`}];
}

return [{name: "err", value: `decode failure`}];
"""
OPTIONS(
  library = ["gs://cdn.polkaholic.io/pako.min.js", "gs://cdn.polkaholic.io/colorfulnotion-decoderData.js", "gs://blockchain-etl-bigquery/ethers-v5.js"]
);

