//
//  URLProtectionSpace.swift
//  flutter_inappwebview
//
//  Created by Lorenzo Pichilli on 19/02/21.
//

import Foundation

extension URLProtectionSpace {
    
    var x509Certificate: Data? {
        guard let serverTrust = serverTrust else {
            return nil
        }
        
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            return nil
        }
        
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let serverCertificate = chain.first else {
            return nil
        }
        return serverCertificate.data
    }
    
    var sslCertificate: SslCertificate? {
        var sslCertificate: SslCertificate? = nil
        if let x509Certificate = x509Certificate {
            sslCertificate = SslCertificate(x509Certificate: x509Certificate)
        }
        return sslCertificate
    }
    
    var sslError: SslError? {
        guard let serverTrust = serverTrust else {
            return nil
        }
        
        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            return nil
        }
        
        var secResult = SecTrustResultType.invalid
        guard SecTrustGetTrustResult(serverTrust, &secResult) == errSecSuccess else {
            return SslError(errorType: .invalid)
        }
        
        guard secResult != .proceed else {
            return nil
        }
        
        return SslError(errorType: secResult)
    }
    
    public func toMap () -> [String:Any?] {
        return [
            "host": host,
            "protocol": self.protocol,
            "realm": realm,
            "port": port,
            "sslCertificate": sslCertificate?.toMap(),
            "sslError": sslError?.toMap(),
            "authenticationMethod": authenticationMethod,
            "distinguishedNames": distinguishedNames,
            "receivesCredentialSecurely": receivesCredentialSecurely,
            "proxyType": proxyType
        ]
    }
}
