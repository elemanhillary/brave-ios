// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Data
import Shared
import WebKit

private let log = Logger.browserLogger

let popup = PaymentHandlerPopupView(imageView: nil, title: Strings.paymentRequestTitle, message: "")

class PaymentRequestExtension: NSObject {
    fileprivate weak var tab: Tab?
    fileprivate var response = ""
    
    init(tab: Tab) {
        self.tab = tab
    }
}

extension PaymentRequestExtension: TabContentScript {
    static func name() -> String {
        return "PaymentRequest"
    }
    
    func scriptMessageHandlerName() -> String? {
        return "PaymentRequest"
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if message.name == "PaymentRequest", let body = message.body as? NSDictionary {
            guard let name = body["name"] as? String, let supportedInstruments = body["supportedInstruments"] as? String, let details = body["details"] as? String else {
                return
            }
            if name == "payment-request-show" {
                do {
                    popup.clearDisplayItems()
                    popup.removeAllButtons()
                    popup.addTotalLabel(message: "")
                    
                    guard let detailsData = details.data(using: String.Encoding.utf8), let supportedInstrumentsData = supportedInstruments.data(using: String.Encoding.utf8) else {
                        log.error("Error parsing data")
                        return
                    }
                    let details = try JSONDecoder().decode(PaymentRequestDetailsHandler.self, from: detailsData)
                    
                    let supportedInstruments =  try JSONDecoder().decode([PaymentRequestSupportedInstrumentsHandler].self, from: supportedInstrumentsData)
                    
                    for item in details.displayItems {
                        popup.addDisplayItemLabel(message: item.label + ":  " + item.amount.value + " " + item.amount.currency + "\n")
                        log.info(item.label)
                    }
                    
                    popup.addTotalLabel(message: details.total.label + ":  " + details.total.amount.value + " " + details.total.amount.currency + "\n")
                    
                    popup.addButton(title: Strings.paymentRequestPay) { [weak self] in
                        guard let self = self else {
                            return .flyDown
                        }
                        guard let rewards = self.tab?.rewards, let publisher = self.tab?.publisher, let amount = Double(details.total.amount.value) else {
                            return .flyDown
                        }
                        
                        rewards.ledger.tipPublisherDirectly(publisher, amount: amount, currency: "BAT") { _ in
                          // TODO: Handle started tip process
                            self.response = """
                                {
                                  "requestId": "a62c29b3-f840-47cd-b895-4573d3190227",
                                  "methodName": "bat",
                                  "details": {
                                    "transaction_id": "bcbbd947-346d-439f-96b4-101bbd966675",
                                    "message": "Payment for Brave T-Shirt!"
                                  }
                                }
                            """
                            
                            ensureMainThread {
                               
                                let trimmed = self.response.removingNewlines()
                                self.tab?.webView?.evaluateJavaScript("paymentreq_postCreate('\(trimmed)')", completionHandler: { _, error in
                                    if error != nil {
                                        log.error(error)
                                    }
                            }) }
                        }
                        
                        
                        return .flyDown
                    }
                    
                    popup.addButton(title: Strings.paymentRequestCancel) { () -> PopupViewDismissType in
                        return .flyDown
                    }
                    
                    log.info("Success!")
                } catch {
                    log.info(error)
                }
                popup.showWithType(showType: .flyUp)
            }
        }
    }
}

extension String {
    func removingNewlines() -> String {
        return components(separatedBy: .newlines).joined()
    }
}

extension Strings {
    public static let paymentRequestTitle = NSLocalizedString("paymentRequestTitle", tableName: "BraveShared", bundle: Bundle.braveShared, value: "Review your payment", comment: "Title for Brave Payments")
    public static let paymentRequestPay = NSLocalizedString("paymentRequestPay", tableName: "BraveShared", bundle: Bundle.braveShared, value: "Pay", comment: "Pay button on Payment Request screen")
    public static let paymentRequestCancel = NSLocalizedString("paymentRequestCancel", tableName: "BraveShared", bundle: Bundle.braveShared, value: "Cancel", comment: "Canceel button on Payment Request screen")
}
