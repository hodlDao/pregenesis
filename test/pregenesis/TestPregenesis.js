const { time, expectEvent} = require("@openzeppelin/test-helpers");
const PreGenesis = artifacts.require('PreGenesis');
const USDCToken = artifacts.require('LpToken');
const MultiSignature = artifacts.require("multiSignature");
const assert = require('chai').assert;
const Web3 = require('web3');
const BN = require("bignumber.js");
var utils = require('../utils.js');

web3 = new Web3(new Web3.providers.HttpProvider("http://127.0.0.1:7545"));

/**************************************************
 test case only for the ganahce command
 ganache-cli --port=7545 --gasLimit=8000000 --accounts=10 --defaultBalanceEther=100000 --blockTime 1
 **************************************************/
// 现在一般都是1个小时结息一次，
// 计算器算一下,
//     _interestRate = (1.05)^(1/24)-1,decimals=27，_interestInterval = 3600
//
// 1.0020349912970346474243981869599-1 = 0.0020349912970346474243981869599，再*1e27就行了
let YEAR_INTEREST = new BN("0.6");
let DAY_INTEREST = YEAR_INTEREST.div(new BN(365));//日利息 5%0
//let DAY_INTEREST = new BN(0.005);
let INTEREST_RATE = new BN("1").plus(new BN(DAY_INTEREST));
let DIV24= new BN("1").div(24);//div one day 24 hours
INTEREST_RATE = Math.pow(INTEREST_RATE,DIV24) - 1;

console.log("INTEREST_RATE",INTEREST_RATE);
INTEREST_RATE = new BN(INTEREST_RATE).times(new BN("1000000000000000000000000000"));

console.log("INTEREST_RATE "+INTEREST_RATE.toString(10));
//return;

contract('PreGenesis', function (accounts){

  let stakeAmount = web3.utils.toWei('10', 'ether');
  let startBlock = 0;

  let staker1 = accounts[2];
  let staker2 = accounts[3];

  let teamMember1 = accounts[4];
  let teamMember2 = accounts[5];
  let teammems = [teamMember1,teamMember2];
  let teammemsRatio = [20,80];

  let operator0 = accounts[7];
  let operator1 = accounts[8];

  let mocksc = accounts[9];

  let VAL_1M = '1000000'+'000000';
  let VAL_10M = '10000000'+'000000';


  let minutes = 60;
  let hour    = 60*60;
  let eightHour = 8*hour;
  let day     = 24*hour;
  let totalPlan  = 0;

  let preGenesisinst;

  let usdc;//stake token

  let mulSiginst;



  before("init", async()=>{


   //setup multisig
  let addresses = [accounts[7],accounts[8],accounts[9]];
  mulSiginst = await MultiSignature.new(addresses,0,{from : accounts[0]});
  console.log(mulSiginst.address);
//////////////////////LP POOL SETTING///////////////////////////////////////////////////
  usdc = await USDCToken.new("USDC",6);
  await usdc.mint(staker1,VAL_10M);
  await usdc.mint(staker2,VAL_10M);

//set phxfarm///////////////////////////////////////////////////////////
  preGenesisinst = await PreGenesis.new(mulSiginst.address,operator0,operator1,usdc.address,mocksc);
  console.log("pregenesis address:", preGenesisinst.address);


  let block = await web3.eth.getBlock("latest");
  startTime = block.timestamp + 1000;
  console.log("set block time",startTime);

  let endTime = startTime + 3600*24*365;

      // function initContract(uint256 _interestRate,uint256 _interestInterval,
      //     uint256 _assetCeiling,uint256 _assetFloor)
//////////////////////////////////////////////////////////////////////////////////////////
  {
      let msgData = preGenesisinst.contract.methods.initContract(INTEREST_RATE.toString(10),eightHour,VAL_10M,0).encodeABI();
      let hash = await utils.createApplication(mulSiginst, operator0, preGenesisinst.address, 0, msgData);
      let index = await mulSiginst.getApplicationCount(hash);
      index = index.toNumber() - 1;
      console.log(index);

      await mulSiginst.signApplication(hash, index, {from: accounts[7]});
      await mulSiginst.signApplication(hash, index, {from: accounts[8]});
  }
      //set interest rate
      res = await preGenesisinst.initContract(INTEREST_RATE,eightHour,VAL_10M,0,{from:operator0});
      assert.equal(res.receipt.status,true);

      {
          let msgData = preGenesisinst.contract.methods.setDepositStatus(true).encodeABI();
          let hash = await utils.createApplication(mulSiginst, operator0, preGenesisinst.address, 0, msgData);
          let index = await mulSiginst.getApplicationCount(hash);
          index = index.toNumber() - 1;
          console.log(index);

          await mulSiginst.signApplication(hash, index, {from: accounts[7]});
          await mulSiginst.signApplication(hash, index, {from: accounts[8]});
      }
      res = await preGenesisinst.setDepositStatus(true,{from:operator0});
      assert.equal(res.receipt.status,true);
  })

  it("[0010] stake in,should pass", async()=>{
    time.increase(7200);//2000 sec
    ////////////////////////staker1///////////////////////////////////////////////////////////
    let res = await usdc.approve(preGenesisinst.address,VAL_1M,{from:staker1});
    assert.equal(res.receipt.status,true);
    time.increase(1000);

    res = await preGenesisinst.deposit(VAL_1M,{from:staker1});
    assert.equal(res.receipt.status,true);

    time.increase(day+1);

    res = await preGenesisinst.getBalance(staker1);
    console.log(res[0].toString(),res[1].toString());

    await usdc.approve(preGenesisinst.address,VAL_1M,{from:staker1});
    res = await preGenesisinst.deposit(VAL_1M,{from:staker1});
    assert.equal(res.receipt.status,true);

    res = await preGenesisinst.getBalance(staker1);
    console.log(res[0].toString(),res[1].toString());
  })

  it("[0020] transfer vcoin,should pass", async()=>{
        let res = await preGenesisinst.getBalance(mocksc);
        console.log("pre sc balance",res[0].toString(),res[1].toString());

        res = await preGenesisinst.getBalance(staker1);
        console.log("pre staker1 balance",res[0].toString(),res[1].toString());

        res = await preGenesisinst.transferVCoin(VAL_1M,{from:staker1});
        assert.equal(res.receipt.status,true);

        res = await preGenesisinst.getBalance(mocksc);
        console.log("after sc balance",res[0].toString(),res[1].toString());

        res = await preGenesisinst.getBalance(staker1);
        console.log("after staker1 balance",res[0].toString(),res[1].toString());
   })

    it("[0030] transfer coind to sc,should pass", async()=>{
        {
            let msgData = preGenesisinst.contract.methods.TransferCoinToTarget().encodeABI();
            let hash = await utils.createApplication(mulSiginst, operator0, preGenesisinst.address, 0, msgData);
            let index = await mulSiginst.getApplicationCount(hash);
            index = index.toNumber() - 1;
            console.log(index);

            await mulSiginst.signApplication(hash, index, {from: accounts[7]});
            await mulSiginst.signApplication(hash, index, {from: accounts[8]});
        }

        let preUsdcBal = await usdc.balanceOf(mocksc);
        console.log("pre usdc balance",preUsdcBal)
        res = await preGenesisinst.TransferCoinToTarget({from:operator0});
        assert.equal(res.receipt.status,true);

        let afterUsdcBal = await usdc.balanceOf(mocksc);
        console.log("after usdc balance",afterUsdcBal)
    })

    it("[0040] user withdraw,should pass", async()=>{
        let res;
        try {
            res = await preGenesisinst.withdraw({from: staker1});
        }catch(e) {
            res = false;
        }
        assert.equal(res,false);

        {
            let msgData = preGenesisinst.contract.methods.setWithdrawStatus(true).encodeABI();
            let hash = await utils.createApplication(mulSiginst, operator0, preGenesisinst.address, 0, msgData);
            let index = await mulSiginst.getApplicationCount(hash);
            index = index.toNumber() - 1;
            console.log(index);

            await mulSiginst.signApplication(hash, index, {from: accounts[7]});
            await mulSiginst.signApplication(hash, index, {from: accounts[8]});
        }

        res = await preGenesisinst.setWithdrawStatus(true,{from:operator0});
        assert.equal(res.receipt.status,true);

       await usdc.mint(preGenesisinst.address,VAL_10M);
        let preUsdcBal = await usdc.balanceOf(staker1);
        console.log("staker1 pre usdc balance",preUsdcBal.toString(10))

        res = await preGenesisinst.withdraw({from:staker1});
        assert.equal(res.receipt.status,true);

        let afterUsdcBal = await usdc.balanceOf(staker1);
        console.log("staker1 after usdc balance",afterUsdcBal.toString(10))
    })

})