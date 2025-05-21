// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol"; // Podstawowa implementacja tokena ERC721
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol"; // Rozszerzenie dla przechowywania metadanych URI
import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // Ochrona przed atakami typu reentrancy
import "@openzeppelin/contracts/utils/Counters.sol"; // Bezpieczne liczniki (ID tokenów)
import "@openzeppelin/contracts/interfaces/IERC2981.sol"; // Interfejs dla obsługi prowizji (royalties)
import "./VerificationManager.sol";

/// @title RealTokenERC721 – Tokenizacja nieruchomości w standardzie ERC721
contract RealTokenERC721 is ERC721, ERC721URIStorage, ReentrancyGuard, IERC2981 {
    using Counters for Counters.Counter;
    using Strings for uint32;

    Counters.Counter private _tokenIds; 
    VerificationManager public verificationManager; // Referencja do kontraktu zarządzającego weryfikacją

    // URL do metadanych IPFS (przez Pinata)
    string private constant pinataGate = "https://gateway.pinata.cloud/ipfs/"; 

    // Zmienne dla prowizji (royalty)
    address private _royaltyReceiver; // Adres odbiorcy opłat
    uint32 private _royaltyPercent;   // Wysokość opłat (w %)

    // Event informujący o tokenizacji nieruchomości
    event PropertyTokenized(
        address indexed owner, 
        uint256 tokenID
    );
    
    // Event dla transferów tokenów
    event TokenTransfer(
        address indexed from, 
        address indexed to, 
        uint256 tokenId, 
        uint256 amount
    );

    // Event informujący o zmianie odbiorcy lub wysokości prowizji
    event RoyaltyUpdated(address indexed receiver, uint256 bps);

    /// @notice Inicjalizacja kontraktu
    /// @param _verificationManager Adres kontraktu VerificationManager
    constructor(address _verificationManager) ERC721("RealTokenERC721", "RT721") {
        verificationManager = VerificationManager(_verificationManager);
        _royaltyReceiver = msg.sender; 
        _royaltyPercent = 1;           
        emit RoyaltyUpdated(_royaltyReceiver, _royaltyPercent);
    }

    /// @notice Funkcja do tokenizacji nieruchomości (mintowania NFT)
    /// @param estateID - identyfikator nieruchomości
    /// @param amount - ilość tokenów (dla ERC721 wymagane 1)
    function tokenizeProperty(uint32 estateID, uint256 amount, string calldata metadataAddress) external nonReentrant {
        require(verificationManager.isVerifiedUser(msg.sender), "Only verified users can tokenize");
        require(amount == 1, "Only 1 token with ERC721");

        // Sprawdzenie czy nieruchomość jest zweryfikowana
        require(verificationManager.isVerifiedEstate(estateID), "EstateID not verified");

        // Sprawdzenie, czy nieruchomość nie została już stokenizowana
        require(!verificationManager.isTokenized(estateID), "Estate already tokenized");
        verificationManager.markEstateAsTokenized(estateID);

        // Mintowanie nowego tokena
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        _safeMint(msg.sender, newTokenId);

        // Tworzenie pełnego URI do metadanych w IPFS
        string memory ipfsURI = string(abi.encodePacked(pinataGate, metadataAddress));
        _setTokenURI(newTokenId, ipfsURI);

        emit PropertyTokenized(msg.sender, newTokenId);
    }

    /// @notice Transfer tokena (tylko dla zweryfikowanych użytkowników)
    function transferProperty(address to, uint256 tokenId) public nonReentrant {
        require(verificationManager.isVerifiedUser(msg.sender), "Sender must be verified");
        require(verificationManager.isVerifiedUser(to), "Recipient must be verified");

        safeTransferFrom(msg.sender, to, tokenId);
        emit TokenTransfer(msg.sender, to, tokenId, 1);
    }

    /// @notice Funkcja z interfejsu IERC2981 – informacje o prowizji
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view override
        returns (address receiver, uint256 royaltyAmount)
    {
        ownerOf(tokenId); // Weryfikacja istnienia tokena
        receiver = _royaltyReceiver;
        royaltyAmount = (salePrice * _royaltyPercent) / 100;

        return (receiver, royaltyAmount);
    }

    /// @notice Funkcja do zmiany odbiorcy i wysokości prowizji
    function setRoyalty(address newReceiver, uint32 newRoyaltyPercent) external {
        require(msg.sender == _royaltyReceiver, "Only royalty receiver can update");
        require(newReceiver != address(0), "Invalid receiver address");
        require(newRoyaltyPercent <= 5, "Royalty exceeds 5%");

        _royaltyReceiver = newReceiver;
        _royaltyPercent = newRoyaltyPercent;
        emit RoyaltyUpdated(newReceiver, newRoyaltyPercent);
    }

    /// @notice Zmiana URI metadanych tokena
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual override {
        super._setTokenURI(tokenId, _tokenURI);
    }

    /// @notice Odczyt URI metadanych tokena
    function tokenURI(uint256 tokenId) public view virtual 
        override(ERC721, ERC721URIStorage) 
        returns (string memory) 
    {
        return super.tokenURI(tokenId);
    }

    /// @notice Obsługa interfejsów (ERC721, ERC721URIStorage, IERC2981)
    function supportsInterface(bytes4 interfaceId) public view virtual 
        override(ERC721, ERC721URIStorage, IERC165) 
        returns (bool) 
    {
        return interfaceId == type(IERC2981).interfaceId || 
               super.supportsInterface(interfaceId);
    }
}