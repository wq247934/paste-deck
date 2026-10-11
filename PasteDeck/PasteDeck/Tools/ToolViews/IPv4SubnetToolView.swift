//
//  IPv4SubnetToolView.swift
//  PasteDeck
//
//  IPv4 / 子网工具：地址校验、类型判断与 CIDR 子网计算。
//  支持裸地址（按 /32 单主机）与 "a.b.c.d/p" CIDR 输入，
//  正确处理 /0、/31、/32 边界。计算全部走 IPv4Math。
//

import SwiftUI

struct IPv4SubnetToolView: View {
    let context: ToolContext

    @State private var inputText: String
    @State private var geoState: GeoState = .idle
    @State private var geoCache: [String: IPGeoResult] = [:]

    /// 归属地查询的界面状态。
    enum GeoState: Equatable {
        case idle
        case loading
        case loaded(IPGeoResult)
        case failed(String)
        case notQueryable
    }

    init(context: ToolContext) {
        self.context = context
        _inputText = State(initialValue: context.prefilledText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    private var parsed: (address: IPv4Math.Address, subnet: IPv4Math.Subnet)? {
        IPv4Math.parseSubnet(inputText)
    }

    private var inputErrorText: String? {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard parsed == nil else { return nil }
        return "无效的 IPv4 地址或 CIDR：例如 10.0.0.137 或 192.168.1.0/24"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                inputSection

                if let parsed {
                    addressInfoSection(parsed: parsed)
                    geoSection(parsed: parsed)
                    subnetSection(parsed.subnet)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 输入

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("IPv4 地址或 CIDR 网段")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            TextField("例如 220.173.103.110 或 192.168.1.0/24", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, design: .monospaced))

            if let errorText = inputErrorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - 地址信息

    private func addressInfoSection(parsed: (address: IPv4Math.Address, subnet: IPv4Math.Subnet)) -> some View {
        let kind = IPv4Math.kind(of: parsed.address)

        return VStack(alignment: .leading, spacing: 8) {
            ToolSectionHeader(title: "地址信息")

            ToolCard {
                ToolResultRow(label: "地址", value: parsed.address.dottedString)
                Divider()
                ToolResultRow(label: "类型", value: kind.displayName, monospaced: false)
                Divider()
                ToolResultRow(label: "前缀长度", value: "/\(parsed.subnet.prefixLength)")
                if parsed.subnet.prefixLength == 32 {
                    Divider()
                    Text("未提供前缀，按单主机 /32 处理；可输入 a.b.c.d/p 查看网段")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - 归属地 / 运营商（在线查询）

    private func geoSection(parsed: (address: IPv4Math.Address, subnet: IPv4Math.Subnet)) -> some View {
        let ip = parsed.address.dottedString
        let queryable = IPGeoService.isQueryable(parsed.address)

        return VStack(alignment: .leading, spacing: 8) {
            ToolSectionHeader(title: "归属地 / 运营商")

            ToolCard {
                HStack(spacing: 10) {
                    Button {
                        queryGeo(ip: ip)
                    } label: {
                        HStack(spacing: 5) {
                            if case .loading = geoState {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Image(systemName: "location.circle")
                                .font(.system(size: 11, weight: .medium))
                            Text(queryable ? "查询归属地" : "私网地址无归属地")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!queryable || isGeoLoading)
                    .opacity(queryable ? 1 : 0.45)
                    .help(queryable ? "向 ipwho.is 在线查询该 IP 的归属地与运营商" : "私有、回环或保留地址没有公网归属信息")

                    switch geoState {
                    case .idle:
                        Text("点击按钮后才会向 ipwho.is 发送该 IP 进行查询")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    case .loading:
                        Text("正在查询…")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                            .lineLimit(2)
                    case .notQueryable:
                        EmptyView()
                    case .loaded:
                        EmptyView()
                    }
                    Spacer()
                }
                .padding(.vertical, 6)

                if case .loaded(let result) = geoState {
                    Divider()
                    ToolResultRow(label: "归属地", value: result.location, monospaced: false)
                    Divider()
                    ToolResultRow(label: "运营商", value: result.isp, monospaced: false)
                    if let asn = result.asn {
                        Divider()
                        ToolResultRow(label: "ASN", value: asn)
                    }
                    if let timezone = result.timezone {
                        Divider()
                        ToolResultRow(label: "时区", value: timezone, monospaced: false)
                    }
                    Divider()
                    Text("数据来源 \(result.source)，仅供参考；IP 归属可能与实际注册信息有差异")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                }
            }
        }
        .onAppear { syncGeoState(for: parsed) }
        .onChange(of: parsed.address) { _, newAddress in
            syncGeoState(for: (newAddress, parsed.subnet))
        }
    }

    private var isGeoLoading: Bool {
        if case .loading = geoState { return true }
        return false
    }

    /// 切换输入 IP 时优先展示缓存，未查询过的回到待查询状态。
    private func syncGeoState(for parsed: (address: IPv4Math.Address, subnet: IPv4Math.Subnet)) {
        guard IPGeoService.isQueryable(parsed.address) else {
            geoState = .notQueryable
            return
        }
        if let cached = geoCache[parsed.address.dottedString] {
            geoState = .loaded(cached)
        } else if case .loaded = geoState {
            geoState = .idle
        }
    }

    private func queryGeo(ip: String) {
        guard let address = IPv4Math.Address.parse(ip), IPGeoService.isQueryable(address) else {
            geoState = .failed(IPGeoError.privateAddress.localizedDescription)
            return
        }
        if let cached = geoCache[ip] {
            geoState = .loaded(cached)
            return
        }
        geoState = .loading
        Task {
            do {
                let result = try await IPGeoService.query(address)
                await MainActor.run {
                    geoCache[ip] = result
                    // 请求返回时输入可能已切换，只有仍指向该 IP 才展示。
                    if self.parsed?.address.dottedString == ip {
                        self.geoState = .loaded(result)
                    }
                }
            } catch {
                await MainActor.run {
                    if self.parsed?.address.dottedString == ip {
                        self.geoState = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: - 子网信息

    private func subnetSection(_ subnet: IPv4Math.Subnet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolSectionHeader(title: "子网信息")

            ToolCard {
                ToolResultRow(label: "子网掩码", value: subnet.mask.dottedString)
                Divider()
                ToolResultRow(label: "通配符掩码", value: subnet.wildcardMask.dottedString)
                if !subnet.isSingleHost {
                    Divider()
                    ToolResultRow(label: "网络地址", value: subnet.network.dottedString)
                    Divider()
                    ToolResultRow(label: "广播地址", value: subnet.broadcast.dottedString)
                }
                Divider()
                ToolResultRow(label: "可用范围", value: usableRangeText(subnet))
                Divider()
                ToolResultRow(label: "地址数量", value: countText(subnet))
            }

            if subnet.prefixLength == 31 {
                Text("该网段为 RFC 3021 点对点链路，两个地址均可直接使用")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func usableRangeText(_ subnet: IPv4Math.Subnet) -> String {
        if subnet.isSingleHost {
            return subnet.firstUsable.dottedString
        }
        return "\(subnet.firstUsable.dottedString) ~ \(subnet.lastUsable.dottedString)"
    }

    private func countText(_ subnet: IPv4Math.Subnet) -> String {
        let total = QuotaFormat.groupedNumber(Double(subnet.totalAddressCount))
        let usable = QuotaFormat.groupedNumber(Double(subnet.usableAddressCount))
        return "共 \(total) 个，可用 \(usable) 个"
    }
}
