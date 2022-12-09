CREATE OR REPLACE FUNCTION `abi_functions`.PARSE_EVENT(abi STRING, functionname STRING, logtopics ARRAY<STRING>, logdata STRING) RETURNS ARRAY<STRUCT<arg STRING, val STRING>> LANGUAGE js AS """
abi = JSON.parse(abi);
    var interface_instance = new ethers.utils.Interface(abi);
    // PunkBidEntered (index_topic_1 uint256 punkIndex, uint256 value, index_topic_2 address fromAddress)
    // PunkBidEntered(uint256,uint256,address)
    // JSON.stringify(pt)
    // var topicID = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('PunkBidEntered(uint256,uint256,address)'));
    // {"anonymous":false,"inputs":[{"indexed":true,"name":"punkIndex","type":"uint256"},{"indexed":false,"name":"value","type":"uint256"},{"indexed":true,"name":"fromAddress","type":"address"}],"name":"PunkBidEntered","type":"event"}

    var stripZeros = /^0x0+/;
    var stripAddress = /^0x0{24}/;

    txargs = [];
    txtypes = [];
    res = [];

    // try-catch - input may be malformed.
    try {
//      var pt = interface_instance.parseTransaction({data: dat});

      frag = "";
      abi.forEach(function(x){
        if (x.name == functionname && x.type == "event") {
          frag = x;
        }
      });

      j=1;
      for (i=0; i < frag.inputs.length; i++) {
        typ = frag.inputs[i].type;
        if (frag.inputs[i].indexed) {
          val = logtopics[j];
          j++;
        }
        else {
          val = logdata
        }
        if (typ == "uint256") {
          val = Number(val.replace(stripZeros, '0x'));
        }
        else if (typ == "address") {
          val = val.toLowerCase();
          val = val.replace(stripAddress, '0x');
        }
        res.push({arg:frag.inputs[i].name,val:val});
      }
    } catch(e) {}
    return res;
"""
OPTIONS(library="gs://blockchain-etl-bigquery/ethers.js");
