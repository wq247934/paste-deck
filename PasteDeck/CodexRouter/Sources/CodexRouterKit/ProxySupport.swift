//
//  ProxySupport.swift
//  PasteDeck
//
//  上游请求的代理配置：不使用 / 跟随系统 / 自定义 HTTP(S) / SOCKS5。
//  回环地址（127.0.0.1、localhost、::1）一律绕过代理，避免请求循环。
//

import Foundation

enum ProxySupport {

    /// 构造上游 URLSessionConfiguration。
    static func upstreamConfiguration(proxy: RouterProxyConfig, proxyPassword: String?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldUsePipelining = false
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 3600

        switch proxy.mode {
        case .none:
            configuration.connectionProxyDictionary = [:]
        case .system:
            // 不设置代理字典：跟随系统（SCDynamicStore）默认行为。
            configuration.connectionProxyDictionary = nil
        case .http:
            guard proxy.isCustomConfigured else {
                configuration.connectionProxyDictionary = [:]
                return configuration
            }
            var dictionary: [AnyHashable: Any] = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: proxy.host,
                kCFNetworkProxiesHTTPPort as String: proxy.port,
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: proxy.host,
                kCFNetworkProxiesHTTPSPort as String: proxy.port,
            ]
            if !proxy.username.isEmpty {
                dictionary[kCFProxyUsernameKey as String] = proxy.username
                if let proxyPassword, !proxyPassword.isEmpty {
                    dictionary[kCFProxyPasswordKey as String] = proxyPassword
                }
            }
            configuration.connectionProxyDictionary = dictionary
        case .socks5:
            guard proxy.isCustomConfigured else {
                configuration.connectionProxyDictionary = [:]
                return configuration
            }
            var dictionary: [AnyHashable: Any] = [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: proxy.host,
                kCFNetworkProxiesSOCKSPort as String: proxy.port,
            ]
            if !proxy.username.isEmpty {
                dictionary[kCFProxyUsernameKey as String] = proxy.username
                if let proxyPassword, !proxyPassword.isEmpty {
                    dictionary[kCFProxyPasswordKey as String] = proxyPassword
                }
            }
            configuration.connectionProxyDictionary = dictionary
        }
        return configuration
    }

    /// 上游主机是否属于回环（永远不走代理，防循环）。
    static func targetIsLoopback(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
    }
}
