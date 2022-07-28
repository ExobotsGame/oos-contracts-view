// SPDX-License-Identifier: MIT

// EXOS - Governance Token for Exobots: Omens Of Steel

pragma solidity ^0.8.0;

import "./utils/math/SafeMath.sol";
import "./utils/Ownable.sol";
import "./utils/IUniswapV2Factory.sol";
import "./utils/IUniswapV2Router.sol";
import "./erc/ERC20.sol";
import "./erc/draft-ERC20Permit.sol";
import "./erc/ERC20Votes.sol";


contract ExosToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    using SafeMath for uint256;

    uint public constant MAX_SUPPLY = 150 * (10 ** 6) * (10 ** 18);

    address public constant BUSD = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isMinter;

    mapping(address => bool) public automatedMarketMakerPairs;
    IUniswapV2Router02 public sellingUniswapV2Router;
    IUniswapV2Router02 public liquidityUniswapV2Router;

    bool public waivePurchaseFees;
    uint256 public sellExtraFee;

    uint256 public denominatorFee = 1000;
    uint256 public treasuryFee = 35;
    uint256 public liquidityFee = 10;
    uint256 public nativeFee = 5;
    uint256 public totalFees = treasuryFee.add(liquidityFee).add(nativeFee);

    address payable public treasuryAddress;
    address payable public nativeTreasuryAddress;
    address public airdropAddress = address(0);

    uint256 public swapTokensAtAmount = 10 * (10**3) * (10**18);
    uint256 public maxTokensToSwap = 20 * (10**3) * (10**18);

    MetronDistributor public distributor;

    bool private swapping;

    event MetronDistributed(uint256 value);


    constructor() ERC20("EXOS", "EXOS") ERC20Permit("EXOS") {
        treasuryAddress = payable(address(0));
        nativeTreasuryAddress = payable(address(0));

        sellingUniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        liquidityUniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        distributor = new MetronDistributor(BUSD, address(this));

        address _uniswapV2Pair = IUniswapV2Factory(sellingUniswapV2Router.factory())
            .createPair(address(this), BUSD);
        automatedMarketMakerPairs[_uniswapV2Pair] = true;

        isMinter[owner()] = true;

        isExcludedFromFees[owner()] = true;
        isExcludedFromFees[treasuryAddress] = true;
        isExcludedFromFees[nativeTreasuryAddress] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[address(distributor)] = true;
    }


    /////////////////////
    // OWNER FUNCTIONS //
    /////////////////////

    function updateDistributor(address newAddress) external onlyOwner {
        require(newAddress != address(distributor), "The distributor already has that address");

        MetronDistributor newDistributor = MetronDistributor(newAddress);

        require(newDistributor.owner() == address(this), "The new distributor must be owned by the token contract");

        metronDistributeOnDemand(true, true, true);

        isExcludedFromFees[address(distributor)] = false;
        isExcludedFromFees[address(newDistributor)] = true;

        distributor = newDistributor;
    }

    function setWaivePurchaseFees(bool value) external onlyOwner {
        waivePurchaseFees = value;
    }

    function setSellExtraFee(uint256 value) external onlyOwner {
        require (value < denominatorFee.div(10), "Fee value too high");

        sellExtraFee = value;
    }

    function setDenominatorFee(uint256 value) external onlyOwner {
        denominatorFee = value;
    }

    function setTreasuryFee(uint256 value) external onlyOwner {
        require (value < denominatorFee.div(10), "Fee value too high");

        treasuryFee = value;
        _calculateTotalFees();
    }

    function setLiquiditFee(uint256 value) external onlyOwner {
        require (value < denominatorFee.div(10), "Fee value too high");

        liquidityFee = value;
        _calculateTotalFees();
    }

    function setNativeFee(uint256 value) external onlyOwner {
        require (value < denominatorFee.div(10), "Fee value too high");
        
        nativeFee = value;
        _calculateTotalFees();
    }

    function setSwapTokensAtAmount(uint256 amount) external onlyOwner {
        require (amount < 10 * (10**6) * (10**18), "Value too high");

        swapTokensAtAmount = amount;
    }

    function setMaxTokensToSwap(uint256 amount) external onlyOwner {
        require (amount < 20 * (10**6) * (10**18), "Value too high");

        maxTokensToSwap = amount;
    }

    function setTreasuryAddress(address payable wallet) external onlyOwner {
        require (wallet != address(0), "Zero-address not valid");

        isExcludedFromFees[treasuryAddress] = false;
        treasuryAddress = wallet;
        isExcludedFromFees[treasuryAddress] = true;
    }

    function setNativeTreasuryAddress(address payable wallet) external onlyOwner {
        require (wallet != address(0), "Zero-address not valid");

        isExcludedFromFees[nativeTreasuryAddress] = false;
        nativeTreasuryAddress = wallet;
        isExcludedFromFees[nativeTreasuryAddress] = true;
    }

    function setAirdropAddress(address wallet) external onlyOwner {
        airdropAddress = wallet;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        automatedMarketMakerPairs[pair] = value;
    }

    function updateSellingRouter(address newAddress) external onlyOwner {
        require (newAddress != address(0), "Zero-address not valid");

        sellingUniswapV2Router = IUniswapV2Router02(newAddress);
    }

    function updateLiquidityRouter(address newAddress) external onlyOwner {
        require (newAddress != address(0), "Zero-address not valid");

        liquidityUniswapV2Router = IUniswapV2Router02(newAddress);
    }

    function setMinter(address wallet, bool value) external onlyOwner {
        require (wallet != address(0), "Zero-address not valid");

        isMinter[wallet] = value;
    }

    function excludeFromFees(address account, bool excluded) external onlyOwner {
        require (account != address(0), "Zero-address not valid");

        isExcludedFromFees[account] = excluded;
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) external onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            isExcludedFromFees[accounts[i]] = excluded;
        }
    }

    function mint(address account, uint256 amount) external {
        require(owner() == _msgSender() || isMinter[_msgSender()], "Caller is not owner nor minter");
        require(totalSupply().add(amount) <= MAX_SUPPLY, "Supply cannot exceed MAX_SUPPLY");

        _mint(account, amount);
    }

    function burn(uint256 amount) external {
        require(owner() == _msgSender() || isMinter[_msgSender()], "Caller is not owner nor minter");

        _burn(_msgSender(), amount);
    }

    function metronDistributeOnDemand(bool liquify, bool sendToNative, bool sendToFee) public onlyOwner {
        swapping = true;

        uint256 distributorTokenBalance = balanceOf(address(distributor));
        if(distributorTokenBalance > maxTokensToSwap) {
            distributorTokenBalance = maxTokensToSwap;
        }

        uint256 tokensToSwap = 0;
        uint256 liquidityTokens = 0;
        uint256 nativeTokens = 0;
        uint256 feeTokens = 0;
        if (liquify) {
            liquidityTokens = distributorTokenBalance.mul(liquidityFee).div(totalFees);
            tokensToSwap += liquidityTokens.div(2);
        }

        if (sendToFee) {
            feeTokens = distributorTokenBalance.mul(treasuryFee).div(totalFees);
            tokensToSwap += feeTokens;
        }

        if (sendToNative) {
            nativeTokens = distributorTokenBalance.mul(nativeFee).div(totalFees);
            distributor.transferExos(nativeTreasuryAddress, nativeTokens);
        }

        if (tokensToSwap > 0) {
            uint256 busdReceived = distributor.swapTokensForBusd(sellingUniswapV2Router, tokensToSwap);

            if (liquify) {
                uint256 half = liquidityTokens.div(2);
                uint256 busdAmount = busdReceived.mul(half).div(tokensToSwap);
                distributor.addLiquidity(liquidityUniswapV2Router, half, busdAmount, address(this));
            }

            if (sendToFee) {
                distributor.transferBusd(treasuryAddress);
            }
        }

        swapping = false;
    }

    function rescueBEP20(IERC20 token, address recipient, uint256 amount) external onlyOwner {
        token.transfer(recipient, amount);
    }

    function rescueBEP20Distributor(IERC20 token, address recipient, uint256 amount) external onlyOwner {
        distributor.rescueBEP20(token, recipient, amount);
    }

    function rescueBNB(address payable recipient, uint256 amount) external onlyOwner {
        require (recipient != address(0), "Zero-address not valid");

        recipient.transfer(amount);
    }

    function rescueBNBDistributor(address payable recipient, uint256 amount) external onlyOwner {
        distributor.rescueBNB(recipient, amount);
    }

    ///////////////////////////
    // END - OWNER FUNCTIONS //
    ///////////////////////////


    ///////////////////////
    // PRIVATE FUNCTIONS //
    ///////////////////////

    function _calculateTotalFees() private {
        totalFees = treasuryFee.add(liquidityFee).add(nativeFee);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (from == airdropAddress || to == airdropAddress) {
            super._transfer(from, to, amount);
            return;
        }

		uint256 distributorTokenBalance = balanceOf(address(distributor));
        bool canSwap = distributorTokenBalance >= swapTokensAtAmount;
        bool isPurchase = automatedMarketMakerPairs[from];

        if (canSwap &&
            !swapping &&
            !isPurchase &&
            from != owner() &&
            to != owner()
        ) {
            if (distributorTokenBalance > maxTokensToSwap) {
                distributorTokenBalance = maxTokensToSwap;
            }

            _metronDistribute(distributorTokenBalance);
        }

        bool takeFee = !swapping;

        if (isExcludedFromFees[from] || isExcludedFromFees[to] ||
            (waivePurchaseFees && isPurchase)) {
            takeFee = false;
        }

        if (takeFee) {
        	uint256 fees = amount.mul(totalFees).div(denominatorFee);
        	if (automatedMarketMakerPairs[to]) {
        	    fees += amount.mul(sellExtraFee).div(denominatorFee);
        	}
        	amount = amount.sub(fees);

            if (fees > 0) {
                super._transfer(from, address(distributor), fees);
            }
        }

        super._transfer(from, to, amount);
    }

    function _metronDistribute(uint256 tokens) private {
        swapping = true;

        uint256 nativeTokens = tokens.mul(nativeFee).div(totalFees);
        uint256 liquidityTokens = tokens.mul(liquidityFee).div(totalFees);
        uint256 liquidityTokensHalf = liquidityTokens.div(2);
        uint256 tokensToSwap = tokens.sub(nativeTokens).sub(liquidityTokensHalf);

        // Swap tokens for BUSD
        uint256 busdReceived = distributor.swapTokensForBusd(sellingUniswapV2Router, tokensToSwap);

        // Add liquidity
        uint256 busdForLiquidity = busdReceived.mul(liquidityTokensHalf).div(tokensToSwap);
        distributor.addLiquidity(liquidityUniswapV2Router, liquidityTokensHalf, busdForLiquidity, address(this));

        // Native fees
        distributor.transferExos(nativeTreasuryAddress, nativeTokens);

        // Fees
        distributor.transferBusd(treasuryAddress);

        emit MetronDistributed(tokens);

        swapping = false;
    }

    // The functions below are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }

    /////////////////////////////
    // END - PRIVATE FUNCTIONS //
    /////////////////////////////

}

contract MetronDistributor is Ownable {

    using SafeMath for uint256;

    address public immutable BUSD;
    address public immutable EXOS;

    constructor(address busd, address exos)  {
        require (busd != address(0), "Zero-address not valid for BUSD");
        require (exos != address(0), "Zero-address not valid for EXOS");

        BUSD = busd;
        EXOS = exos;
    }

    function swapTokensForBusd(IUniswapV2Router02 sellingUniswapV2Router, uint256 tokenAmount)
        external onlyOwner returns(uint256) {

        uint256 beforeBalance = IERC20(BUSD).balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = EXOS;
        path[1] = BUSD;

        IERC20(EXOS).approve(address(sellingUniswapV2Router), tokenAmount);

        // Make the swap
        sellingUniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // Accept any amount of BUSD
            path,
            address(this),
            block.timestamp
        );

        uint256 afterBalance = IERC20(BUSD).balanceOf(address(this));
        return afterBalance.sub(beforeBalance);
    }

    function addLiquidity(IUniswapV2Router02 liquidityUniswapV2Router, uint256 tokenAmount, uint256 busdAmount, address to)
        external onlyOwner {
        if (busdAmount > 0) {
            // Approve token transfer to cover all possible scenarios
            IERC20(EXOS).approve(address(liquidityUniswapV2Router), tokenAmount);
            IERC20(BUSD).approve(address(liquidityUniswapV2Router), busdAmount);

            // Add the liquidity
            liquidityUniswapV2Router.addLiquidity(
                EXOS,
                BUSD,
                tokenAmount,
                busdAmount,
                0, // Slippage is unavoidable
                0, // Slippage is unavoidable
                to,
                block.timestamp
            );
        }
    }

    function transferExos(address recipient, uint256 amount) external onlyOwner {
        if (amount > 0) {
            IERC20(EXOS).transfer(recipient, amount);
        }
    }

    function transferBusd(address recipient) external onlyOwner {
        uint256 busdBalance = IERC20(BUSD).balanceOf(address(this));
        if (busdBalance > 0) {
            IERC20(BUSD).transfer(recipient, busdBalance);
        }
    }

    function rescueBEP20(IERC20 token, address recipient, uint256 amount) external onlyOwner {
        token.transfer(recipient, amount);
    }

    function rescueBNB(address payable recipient, uint256 amount) external onlyOwner {
        require (recipient != address(0), "Zero-address not valid");

        recipient.transfer(amount);
    }
}
