// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FunctionsClient} from "@chainlink/contracts@1.3.0/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts@1.3.0/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts@1.3.0/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./VerificationManager.sol";

/// @title ChainlinkConnector – Kontrakt do łączności z wyrocznią Chainlink Funkctions
contract ChainlinkConnector is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    // Referencja do kontraktu zarządzającego weryfikacją
    VerificationManager public verificationManager;

    // Dane ostatniego zapytania Chainlink Functions
    bytes32 public lastRequestId;
    uint32 public lastEstateID;
    bytes public lastError;

    // Router i identyfikator DON dla Chainlink Functions
    address constant ROUTER = 0x234a5fb5Bd614a7AA2FfAB244D603abFA0Ac5C5C; // Arbitrum Sepolia
    bytes32 constant DON_ID = 0x66756e2d617262697472756d2d7365706f6c69612d3100000000000000000000;
    uint32 gasLimit = 300000;

    /// @notice Inicjalizacja kontraktu
    /// @param _verificationManager Adres kontraktu VerificationManager
    constructor(address _verificationManager) FunctionsClient(ROUTER) ConfirmedOwner(msg.sender) {
        verificationManager = VerificationManager(_verificationManager);
    }

    /// @notice Zapytanie do Chainlink Functions, które uruchamia skrypt
    /// @param subscriptionId - ID subskrybcji/konta w Chainlink Functions
    /// @param apiKey - klucz do zewnętrznego API z danymi o nieruchomościach
    function sendRequest(uint64 subscriptionId, string memory apiKey) external onlyOwner returns (bytes32) {
        FunctionsRequest.Request memory req;

        // Przekazywane argumenty do skryptu JavaScript (API key oraz ostatnie ID)
        string[] memory args = new string[](2);
        args[0] = apiKey;
        args[1] = uint256(lastEstateID).toString();

        // Skrypt w JavaScript - pobiera kolejne estateID z API (20 nieruchomości w petli)
        req.initializeRequestForInlineJavaScript(
        "try {"
            "const apiKey = args[0];"
            "const lastEstateID = parseInt(args[1] || '0');"
            "const { error, data } = await Functions.makeHttpRequest({"
            "  url: 'https://api.gateway.attomdata.com/propertyapi/v1.0.0/property/address?postalcode=03110&page=1&pagesize=20',"
            "  headers: { apikey: apiKey }"
            "});"
            "if (error) throw new Error('HTTP request failed');"
            "if (!data || !data.property || !Array.isArray(data.property) || data.property.length === 0) {"
            "  throw new Error('No property data');"
            "}"
            "let nextID = null;"
            "for (let i = 0; i < data.property.length - 1; i++) {"
            "   const estateID = parseInt(data.property[i].identifier.Id);"
            "   if (estateID === lastEstateID) {"
            "       const nextIndex = (i + 1) % data.property.length;"
            "       nextID = parseInt(data.property[nextIndex].identifier.Id);"
            "       break;"
            "   }"
            "}"
            "if (!Number.isInteger(nextID)) {"
            "   nextID = parseInt(data.property[0]?.identifier?.Id || '0');"
            "}"
            "return Functions.encodeUint256(nextID);"
        "} catch (e) {"
            "console.log('JS error:', e.toString());"
            "throw e;"            
        "}"
    );

        req.setArgs(args);

        lastRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            DON_ID
        );

        return lastRequestId;
    }

    /// @notice Funkcja wykonywana automatycznie po otrzymaniu odpowiedzi z Chainlink
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (requestId != lastRequestId) {
            revert("Unexpected request ID");
        }

        // Dekodowanie otrzymanego ID nieruchomości
        lastEstateID = uint32(abi.decode(response, (uint256)));

        verificationManager.verifyProperty(lastEstateID);

        // Zapis błędu (jeśli wystąpił)
        lastError = err;
    }

    /// @notice Możliwość ręcznej zmiany adresu kontraktu VerificationManager
    function setVerificationManager(address _newVM) external onlyOwner {
        verificationManager = VerificationManager(_newVM);
    }

    function setGasLimit(uint32 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }

    // Funkcja testowa — symulacja odpowiedzi z Chainlink
    function testContract(bytes memory chainlinkResponse) external onlyOwner {
        lastEstateID = uint32(abi.decode(chainlinkResponse, (uint256)));
        verificationManager.verifyProperty(lastEstateID);
    }
}
