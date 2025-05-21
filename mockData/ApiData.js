// Skrypt łączy się z API i pobiera dane o nieruchomościach. 
// Dane zostają zaszyfrowane i zapisane w pliku JSON w formacie przygotowanym dla smart kontraktów.
// Przygotowuje tez ściągniete dane do umieszczenia w IPFS via Pinata i tworzy pliki w formacie json dla kazdej nieruchomosci

// Pinata SDK docs: https://docs.pinata.cloud/sdk/getting-started

const { ethers } = require('ethers');
const fs = require('fs');
const ipfsPhotos = require('./ipfsPhotos'); // CIDs
const pinataSDK = require('@pinata/sdk'); // Pinata SDK
const pinataGate = 'https://gateway.pinata.cloud/ipfs/'; // Pinata gateway

// Własny klucz mozna uzyskac na https://api.developer.attomdata.com/
// const apiKey = 'mySecretKey1'; // Testowy klucz autora został ukryty, umieszczony jedynie w celach demonstracyjnych.

//------
const page = 1;
const apiKey = "yourSecretKey";
// -----
const zipCode = '03110'; // Bedford, NY = 03110 ;
const apiUrl = `https://api.gateway.attomdata.com/propertyapi/v1.0.0/property/address?postalcode=${zipCode}&page=${page}&pagesize=20`;

// Wlasny klucz do Pinata mozna uzyskac tu: https://app.pinata.cloud/auth/signin
const pinataApiKey = 'pinataSecretKey';
const pinataSecretKey = 'pinataEvenMoreSecretKey'; 
const pinata = new pinataSDK(pinataApiKey, pinataSecretKey);
const abiCoder = ethers.AbiCoder.defaultAbiCoder(); 

async function processApiData() {
    try {
        const response = await fetch(apiUrl, {
            method: 'GET',
            headers: {
              'Accept': 'application/json',
              'apikey': apiKey
            }
        });
        const data = await response.json();
        fs.writeFileSync('responseRealEstate.json',  JSON.stringify(data, null, 2)); // fullJson from API

        let propertiesList = [];
        let estateIdToIpfsMap = {}; // Map for estateID -> IPFS CID
        //   let dataToEncode = [];

        if (data.property && data.property.length > 0) {
            for (const [index, property] of data.property.entries()) {
                const estateID = property.identifier.Id;
                const name = `Real Estate # ${estateID}`;
                const description = `Token ${property.address.line1}, ${property.address.locality}, ${property.address.postal1}`;
                // const description = `Token nieruchomosci pod adresem: ${property.address.line1}, ${property.address.locality}, ${property.address.postal1}`;
                const image = `${pinataGate}${ipfsPhotos[index % ipfsPhotos.length]}`;

                const metadata = { name, description, image, estateID: Number(estateID) };

                const metadataFileName = `metadata_${estateID}.json`;
                fs.writeFileSync(metadataFileName, JSON.stringify(metadata, null, 2));

                // Upload to Pinata
                const pinataResponse = await pinata.pinFileToIPFS(fs.createReadStream(metadataFileName), {
                    pinataMetadata: { name: metadataFileName }
                });
                const ipfsCid = pinataResponse.IpfsHash;

                // Add to propertiesList and map
                propertiesList.push({ estateID, name, description, image, ipfsCid });
                estateIdToIpfsMap[estateID] = ipfsCid;

                console.log(`estateID: ${estateID}`);
                console.log(`description: ${description}`);
                // console.log(`image: ${image}`);
                console.log(`IPFS CID: ${ipfsCid}`);
            }
            
            let encodedProperties = propertiesList.map(property => {
                // return abi.encodeFunctionData('verifyProperty', [
                // in ethers v5 ethers.utils.defaultAbiCoder
                return abiCoder.encode(['uint32', 'string', 'string'], [ // Dla Ethers v6 const abiCoder = ethers.AbiCoder.defaultAbiCoder().encode()
                    Number(property.estateID),   // estateID (uint32)
                    property.description,        // description / full address (string)
                    property.ipfsCid             // ipfsCid -  (string)
                ]);
            });

            // Zwrocone dane w bytes[]
            const chainlinkPayload = abiCoder.encode(['bytes[]'], [encodedProperties]);
            
            // Zapis plików z danymi - odznaczyć wybrane (pliki załączone)
            // fs.writeFileSync('propertiesList.json', JSON.stringify(propertiesList, null, 2));  // Metadata copy
            fs.writeFileSync('estateIdToIpfsMap.json', JSON.stringify(estateIdToIpfsMap, null, 2));  // Map estateID : metadataAddress
            
        } else {
            console.log('No properties found.');
            console.log('Full response:', JSON.stringify(data, null, 2));
        }
    } catch (error) {
        console.error('Error:', error);
    }
}

processApiData();
