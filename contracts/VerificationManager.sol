// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;


/// @title VerificationManager – Kontrakt do zarządzania weryfikacjami i bezpieczeństwem
contract VerificationManager {
    address public admin;
    address automationAddress; 

    // Mapa ze zweryfikowanymi adresami 
    mapping(address => bool) public isVerifiedUser;

    // Mapa z estateID stokoenizowanych nieruchomości
    mapping(uint32 => bool) public isTokenized;

    // Zweryfikowane nieruchomości i ich adresy IPFS
    mapping(uint32 => bool) public isVerifiedEstate;

    // Eventy informujące o weryfikacji
    event EstateVerified(uint32 estateID, bool isVerifiedEstate);
    event UserVerified(address indexed user, bool isVerifiedUser);
    event EstateTokenized(uint32 indexed estateID);

    constructor() {
        admin = msg.sender;
    }

    // Modyfikatory dostępu
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not authorized");
        _;
    }

    modifier onlyAdminOrChainlink() {
        require(msg.sender == admin || msg.sender == automationAddress, 
        "Not authorized");
        _;
    }

    /// @notice Weryfikacja użytkownika
    function verifyUser(address _user) public onlyAdmin {
        isVerifiedUser[_user] = true;
        emit UserVerified(_user, isVerifiedUser[_user]);
    }

    /// @notice Weryfikacja nowej nieruchomości
    function verifyProperty(uint32 estateID) public {
        if (isVerifiedEstate[estateID]) {
            return;
        }
        isVerifiedEstate[estateID] = true;
        emit EstateVerified(estateID, isVerifiedEstate[estateID]);
    }

    /// @notice Oznacz nieruchomość jako tokenizowaną (tylko raz)
    function markEstateAsTokenized(uint32 _estateID) public {
        require(!isTokenized[_estateID], "Estate already tokenized!");
        isTokenized[_estateID] = true;
        emit EstateTokenized(_estateID);
    }

    /// @notice Weryfikacja wielu użytkowników jednocześnie
    function verifyBatch(address[] memory _users)
        public onlyAdminOrChainlink {
        for (uint i = 0; i < _users.length; i++) {
            isVerifiedUser[_users[i]] = true;
            emit UserVerified(_users[i], isVerifiedUser[_users[i]]);
        }
    }

    /// @notice Zmiana adresu admina — tylko obecny admin
    function setOwner(address newAdmin) external onlyAdmin {
        require(newAdmin != admin, "New owner must be different");
        admin = newAdmin;
    }

    /// @notice Ustawienie adresu automatyzacji (Chainlink)
    function setAutomation(address newAutomation) external onlyAdmin {
        require(newAutomation != automationAddress, "New address must be different");
        automationAddress = newAutomation;
    }

}