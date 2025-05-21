// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./VerificationManager.sol";

/// @title RealTokenERC1155 – Tokenizacja nieruchomości w standardzie ERC1155
contract RealTokenERC1155 is ERC1155, ERC1155URIStorage, ERC1155Supply, ReentrancyGuard, IERC2981 {
    using Counters for Counters.Counter;
    using Strings for uint32;

    Counters.Counter private _tokenIds;
    VerificationManager public verificationManager;

    string private constant PINATA_GATE = "https://gateway.pinata.cloud/ipfs/";

    // Zmienne dla prowizji (royalty)
    address private _royaltyReceiver;
    uint32 private _royaltyPercent;

    // Event informujący o tokenizacji nieruchomości
    event PropertyTokenized(
        address indexed owner, 
        uint256 tokenId, 
        uint256 totalTokens
    );

    // Event informujący o transferze tokenów
    event TokenTransfer(
        address indexed from, 
        address indexed to, 
        uint256 tokenId, 
        uint256 amount
    );

    /// @notice Inicjalizacja kontraktu
    /// @param _verificationManager Adres kontraktu VerificationManager
    constructor(address _verificationManager) ERC1155("") {
        verificationManager = VerificationManager(_verificationManager);
        _royaltyReceiver = msg.sender;
        _royaltyPercent = 1;
    }

    /// @notice Funkcja do tokenizacji nieruchomości (mintowania NFT)
    /// @param estateID - identyfikator nieruchomości
    /// @param amount - ilość tokenów (dla ERC1155 wymagane >1)
    function tokenizeProperty(uint32 estateID, uint256 amount, string calldata metadataAddress) external nonReentrant {
        require(verificationManager.isVerifiedUser(msg.sender), "Only verified users can tokenize");
        require(amount > 0, "Amount must be greater than 0");

        // Sprawdzenie czy nieruchomość jest zweryfikowana
        require(verificationManager.isVerifiedEstate(estateID), "EstateID not verified");
        // Sprawdzenie, czy nieruchomość nie została już stokenizowana
        require(!verificationManager.isTokenized(estateID), "Estate already tokenized");
        verificationManager.markEstateAsTokenized(estateID);

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _mint(msg.sender, newTokenId, amount, "");

        string memory ipfsURI = string(abi.encodePacked(PINATA_GATE, metadataAddress));
        _setURI(newTokenId, ipfsURI);

        emit PropertyTokenized(msg.sender, newTokenId, amount);       
    }

    /// @notice Transfer tokena (tylko dla zweryfikowanych użytkowników)
    function transferProperty(address to, uint256 tokenId, uint256 amount) 
        public 
        nonReentrant 
    {
        require(verificationManager.isVerifiedUser(msg.sender), "Sender must be verified");
        require(verificationManager.isVerifiedUser(to), "Recipient must be verified");

        safeTransferFrom(msg.sender, to, tokenId, amount, "");
        emit TokenTransfer(msg.sender, to, tokenId, amount);
    }

    /// @notice Funkcja z interfejsu IERC2981 – informacje o prowizji
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override
        returns (address receiver, uint256 royaltyAmount)
    {
        require(totalSupply(tokenId) > 0, "Royalty query for nonexistent token");

        receiver = _royaltyReceiver;
        royaltyAmount = (salePrice * _royaltyPercent) / 100;
        return (receiver, royaltyAmount);
    }

    /// @notice Funkcja do zmiany odbiorcy i wysokości prowizji
    function setRoyalty(address newReceiver, uint32 newRoyaltyPercent) 
        external 
    {
        require(msg.sender == _royaltyReceiver, "Only royalty receiver can update");
        require(newReceiver != address(0), "Invalid receiver address");
        require(newRoyaltyPercent <= 5, "Royalty exceeds 5%");

        _royaltyReceiver = newReceiver;
        _royaltyPercent = newRoyaltyPercent;
    }

    /// @notice Zmiana URI metadanych tokena
    function _setURI(uint256 tokenId, string memory tokenURI) internal virtual 
        override (ERC1155URIStorage) 
    {
        super._setURI(tokenId, tokenURI);
    }

    /// @notice Zwraca URI metadanych dla danego tokena
    function uri(uint256 tokenId) public view virtual 
        override(ERC1155, ERC1155URIStorage) 
        returns (string memory) 
    {
        return super.uri(tokenId);
    }

    /// @notice Wymagane nadpisanie interfejsu
    function supportsInterface(bytes4 interfaceId) public view virtual 
        override(ERC1155, IERC165) 
        returns (bool) 
    {
        return interfaceId == type(IERC2981).interfaceId || 
               super.supportsInterface(interfaceId);
    }

    /// @notice Obsługuje aktualizację bilansu tokenów po transferze (wymagane przez ERC1155Supply)
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) 
        internal virtual override(ERC1155, ERC1155Supply) 
    {
        super._update(from, to, ids, values);
    }
}