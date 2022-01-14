
sleep = function sleep(milliSeconds) {
  var startTime = new Date().getTime();
  while (new Date().getTime() < startTime + milliSeconds);
};

pause = async function pause(web3,endBlk) {
  let blkNum = await web3.eth.getBlockNumber();;
  while (blkNum <= endBlk){
    sleep(1000);
    blkNum = await web3.eth.getBlockNumber();
    console.log(blkNum)
  }
  console.log("pause break")
};

async function createApplication(multiSign,account,to,value,message){
    await multiSign.createApplication(to,value,message,{from:account});
    return await multiSign.getApplicationHash(account,to,value,message)
}

async function testSigViolation(message,testFunc){
    try {
        await testFunc();
        return true;
    } catch (error) {
        console.log(error);
        return false;
    }
}
exports.createApplication = createApplication;
exports.testSigViolation = testSigViolation;
exports.sleep = sleep;
exports.pause = pause;
