//
//  TimeLineTableViewController.swift
//  iMast
//
//  Created by rinsuki on 2017/05/24.
//  Copyright © 2017年 rinsuki. All rights reserved.
//

import UIKit
import SwiftyJSON
import Starscream
import Hydra
import ReachabilitySwift

class TimeLineTableViewController: UITableViewController, WebSocketDelegate {
    
    var posts:[JSON] = []
    var socket: WebSocket?
    var streamingNavigationItem: UIBarButtonItem?
    var isUserReasonDisconnected = false
    var postsQueue:[JSON] = []
    var timelineZIndex:Int = 0
    var timelineMinZIndex:Int = 0
    var cellCache:[Int:UITableViewCell] = [:]
    var isAlreadyAdded:[Int:Bool] = [:]
    var readmoreCell: UITableViewCell!
    var maxPostCount = 100
    var isReadmoreLoading = false {
        didSet {
            (readmoreCell.viewWithTag(2) as! UIActivityIndicatorView).alpha = isReadmoreLoading ? 1 : 0
            (readmoreCell.viewWithTag(1) as! UIButton).alpha = isReadmoreLoading ? 0 : 1
        }
    }
    var isReadmoreEnabled = true
    var pleaseNotSettingPostViewHeight = false
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false
        
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        

        tableView.estimatedRowHeight = 100
        tableView.rowHeight = UITableViewAutomaticDimension
        // 引っ張って更新
        refreshControl = UIRefreshControl()
        refreshControl?.addTarget(self, action: #selector(self.refreshTimeline), for: UIControlEvents.valueChanged)
        tableView.addSubview(refreshControl!)
        loadTimeline().then {
            self.tableView.reloadData()
            self.websocketConnect(auto: true)
        }
        
        if self.websocketEndpoint() != nil {
            self.streamingNavigationItem = UIBarButtonItem(image: UIImage(named: "StreamingStatus")!, style: .plain, target: self, action: #selector(self.streamingStatusTapped))
            self.streamingNavigationItem?.tintColor = UIColor.gray
            self.navigationItem.leftBarButtonItems?.append(self.streamingNavigationItem!)
        }
        DispatchQueue(label: "jp.pronama.imast.timelinequeue").async {
            while true {
                while self.postsQueue.count == 0 {
                    usleep(500)
                }
                let posts = self.postsQueue.sorted(by: { (a, b) -> Bool in
                    return a["id"].intValue > b["id"].intValue
                })
                print(posts.map({ (post) -> Int in
                    return post["id"].intValue
                }))
                self.postsQueue = []
                DispatchQueue.main.async {
                    self._addNewPosts(posts: posts)
                }
                sleep(1)
            }
        }
        
        readmoreCell = Bundle.main.loadNibNamed("TimeLineReadMoreCell", owner: self, options: nil)?.first as! UITableViewCell
        readmoreCell.layer.zPosition = CGFloat.infinity
        (readmoreCell.viewWithTag(1) as! UIButton).addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.readMoreTimelineTapped)))
    }
    
    func loadTimeline() -> Promise<Void> {
        print("loadTimelineを実装してください!!!!!!")
        return Promise.init(resolved: Void())
    }
    func refreshTimeline(){
        print("refreshTimelineを実装してください!!!!!!")
        self.refreshControl?.endRefreshing()
    }
    func readMoreTimeline(){
        print("readMoreTimelineを実装してください!!!!!!")
        isReadmoreLoading = false
    }
    
    func readMoreTimelineTapped(sender: UITapGestureRecognizer) {
        isReadmoreLoading = true
        readMoreTimeline()
    }
    
    func addNewPosts(posts: [JSON]) {
        posts.forEach { (post) in
            postsQueue.append(post)
        }
    }
    
    func _addNewPosts(posts posts_: [JSON]) {
        if posts_.count == 0 {
            return
        }
        let myAccount = MastodonUserToken.getLatestUsed()!.screenName!
        let posts: [JSON] = posts_.sorted(by: { (a, b) -> Bool in
            return a["id"].intValue > b["id"].intValue
        }).filter({ (post) -> Bool in
            if (post["sensitive"].boolValue && myAccount != post["account"]["acct"].stringValue) || post["reblog"]["sensitive"].boolValue { // Appleに怒られたのでNSFWだったら隠す
                return false
            }
            if isAlreadyAdded[post["id"].intValue] != true {
                isAlreadyAdded[post["id"].intValue] = true
                return true
            }
            return false
        }).reversed().map({ (post) -> JSON in
            var rpost = post
            rpost["zindex"].int = timelineZIndex
            print(rpost["id"].int, timelineZIndex)
            timelineZIndex += 1
            getCell(post:rpost)
            return rpost
        }).reversed()
        print("hoge")
        
        /*
        if self.posts.count == 0 {
            self.posts = posts
            tableView.reloadData()
            return
        }
         */
        let usingAnimationFlag = self.posts.count != 0
        if usingAnimationFlag {
            self.tableView.beginUpdates()
        }
        var cnt = 0
        var indexPaths: [IndexPath] = []
        var deleteIndexPaths: [IndexPath] = []
        posts.forEach { (post) in
            self.posts.insert(post, at: cnt)
            indexPaths.append(IndexPath(row: cnt, section: 0))
            cnt += 1
            if (post["account"]["avatar_static"].string != nil) {
                var iconUrl = post["account"]["avatar_static"].stringValue
                if iconUrl.count >= 1 && iconUrl[iconUrl.startIndex] == "/" {
                    iconUrl = "https://"+MastodonUserToken.getLatestUsed()!.app.instance.hostName+iconUrl
                }
                _ = getCell(post: post)
                /*
                getImage(url: iconUrl).then { image in
                    // 特に何をするわけでもない
                }
                 */
            }
        }
        if self.posts.count - cnt > maxPostCount { // メモリ節約
            for i in (maxPostCount+cnt)..<self.posts.count {
                deleteIndexPaths.append(IndexPath(row: i - cnt, section: 0))
            }
            self.posts = Array(self.posts.prefix(maxPostCount + cnt))
        }
        if usingAnimationFlag {
            print(indexPaths, deleteIndexPaths)
            self.tableView.insertRows(at: indexPaths, with: .none)
            self.tableView.deleteRows(at: deleteIndexPaths, with: .none)
            self.tableView.endUpdates()
        } else {
            self.tableView.reloadData()
        }
    }
    
    func websocketEndpoint() -> String? {
        return nil
    }
    
    func websocketConnect(auto: Bool) {
        if auto {
            let conditions = UserDefaults.standard.string(forKey: "streaming_autoconnect")
            if conditions == "no" {
                return
            } else if conditions == "wifi" {
                if !(Reachability.init()?.isReachableViaWiFi ?? false) {
                    return
                }
            }
        }
        if self.websocketEndpoint() != nil {
            MastodonUserToken.getLatestUsed()!.app.instance.getInfo().then { infoJSON in
                
                let urlString = String(format: "%@/api/v1/streaming/?access_token=%@&stream=%@",
                                       infoJSON["urls"]["streaming_api"].string ?? "wss://"+MastodonUserToken.getLatestUsed()!.app.instance.hostName,
                                       MastodonUserToken.getLatestUsed()!.token,
                                       self.websocketEndpoint()!
                )
                print(urlString)
                self.socket = WebSocket(url: URL(string: urlString)!)
                self.socket!.delegate = self
                self.socket!.connect()
                websockets.append(self.socket!)
            }
        }
    }
    
    func websocketDidConnect(socket: WebSocket){
        print("WebSocket connected")
        streamingNavigationItem?.tintColor = nil
    }
    
    func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        print("WebSocket Disconnected", error)
        streamingNavigationItem?.tintColor = UIColor(colorLiteralRed: 1, green: 0.3, blue: 0.15, alpha: 1)
        if isUserReasonDisconnected {
            isUserReasonDisconnected = false
            return
        }
        websocketConnect(auto: true)
    }
    
    func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        var object = JSON(parseJSON: text)
        print(object)
        if object["event"].string == "update" {
            object["payload"] = JSON(parseJSON: object["payload"].string ?? "{}")
            /*
            self.tableView.beginUpdates()
            self.posts.insert(object["payload"], at: 0)
            let indexPath = IndexPath(row: 0, section: 0)
            self.tableView.insertRows(at: [indexPath], with: .automatic)
            self.tableView.endUpdates()
             */
            addNewPosts(posts: [object["payload"]])
        } else if object["event"].string == "delete" {
            var tootFound = false
            self.posts = self.posts.filter({ (post) -> Bool in
                if post["id"].intValue != object["payload"].intValue {
                    return true
                }
                tootFound = true
                return false
            })
            if tootFound {
                self.tableView.reloadData()
            }
        }
    }
    
    func websocketDidReceiveData(socket: WebSocket, data: Data) {
        print("WebSocket data recivied")
    }
    
    func streamingStatusTapped() {
        print("called")
        let nowStreamConnected = (socket?.isConnected ?? false)
        let alertVC = UIAlertController(title: "ストリーミング", message: "現在: " + ( nowStreamConnected ? "接続中" : "接続していません"), preferredStyle: .actionSheet)
        alertVC.popoverPresentationController?.sourceView = self.streamingNavigationItem?.value(forKey: "view") as! UIView
        alertVC.popoverPresentationController?.sourceRect = (self.streamingNavigationItem?.value(forKey: "view") as! UIView).frame
        if nowStreamConnected {
            alertVC.addAction(UIAlertAction(title: "切断", style: .default, handler: { (action) in
                self.isUserReasonDisconnected = true
                self.socket?.disconnect()
            }))
        } else {
            alertVC.addAction(UIAlertAction(title: "接続", style: .default, handler: { (action) in
                self.websocketConnect(auto: false)
            }))
        }
        alertVC.addAction(UIAlertAction(title: "強制再描画", style: .default, handler: { (action) in
            let posts = self.posts
            self.posts = []
            self.tableView.reloadData()
            let isStreamingConnectingNow = self.socket?.isConnected ?? false
            if isStreamingConnectingNow {
                self.socket?.disconnect()
                self.isUserReasonDisconnected = true
            }
            DispatchQueue(label: "jp.pronama.imast.redrawqueue").async {
                sleep(1)
                self.cellCache = [:]
                var backId = 0
                let sorted_posts: [JSON] = posts.sorted(by: { (a, b) -> Bool in
                    return a["id"].intValue > b["id"].intValue
                }).filter({ (post) -> Bool in
                    if backId == post["id"].intValue {
                        return false
                    }
                    backId = post["id"].intValue
                    return true
                }).reversed().map({ (post) -> JSON in
                    var rpost = post
                    rpost["zindex"].int = self.timelineZIndex
                    self.timelineZIndex += 1
                    return rpost
                }).reversed()
                DispatchQueue.main.async {
                    self.refreshControl?.endRefreshing()
                    sorted_posts.forEach({ (post) in
                        _ = self.getCell(post: post)
                    })
                    self.tableView.subviews[0].subviews.forEach({ (view) in
                        view.removeFromSuperview()
                    })
                    print(self.tableView.visibleCells)
                    self.posts = sorted_posts
                    self.tableView.reloadData()
                    if isStreamingConnectingNow {
                        self.socket?.connect()
                    }
                }
            }
        }))
        alertVC.addAction(UIAlertAction(title: "再取得",  style: .default, handler: { (action) in
            let isStreamingConnectingNow = self.socket?.isConnected ?? false
            if isStreamingConnectingNow {
                self.socket?.disconnect()
                self.isUserReasonDisconnected = true
            }
            self.posts = []
            self.tableView.reloadData()
            self.isAlreadyAdded = [:]
            self.loadTimeline().then {
                print(self.posts)
                self.posts.forEach({ (post) in
                    _ = self.getCell(post: post)
                })
                self.tableView.reloadData()
                if isStreamingConnectingNow {
                    self.socket?.connect()
                }
            }
        }))
        alertVC.addAction(UIAlertAction(title: "キャンセル", style: .cancel, handler: nil))
        present(alertVC, animated: true, completion: nil)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return posts.count == 0 ? 0 : posts.count + (isReadmoreEnabled ? 1 : 0)
    }
    
    func getCell(post: JSON) -> UITableViewCell {
        if cellCache[post["id"].intValue] != nil {
            return cellCache[post["id"].intValue]!
        }
        let cell = UITableViewCell()
        // Configure the cell...
        let postView = MastodonPostView()
        postView.layoutIfNeeded()
        postView.layoutSubviews()
        postView.load(json: post)
        // ↓iOS9切ったら消す
        if  #available(iOS 10.0, *) {
            if(!pleaseNotSettingPostViewHeight) {
                postView.frame = CGRect(x:0, y:0, width: tableView.frame.width, height: 16544)
            }
        } else {
            postView.frame = CGRect(x:0, y:0, width: tableView.frame.width, height: 200)
        }
        
        cell.contentView.subviews.forEach { (subView) in
            subView.removeFromSuperview()
        }
        cell.contentView.addSubview(postView)
        cell.contentView.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "H:[postView(==view)]",
            options: .alignAllTop,
            metrics: nil,
            views: ["view": cell.contentView,"postView": postView]))
        cell.contentView.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "V:[view(>=postView)]",
            options: .alignAllTop,
            metrics: nil,
            views: ["view": cell.contentView,"postView": postView]).map({ (constraint) -> NSLayoutConstraint in
                constraint.priority = 1000
                return constraint
            })
        )
        /*
         * 後に描画されたCellのY座標が先に描画されたCellのY座標より上の場合、謎のpaddingが下に発生して他のCellの部分を上書きしてしまう現象の対処。
         * Webエンジニア的な考え方で解決。
         * たぶん後で壊れる
         */
        cell.layer.zPosition = CGFloat(-Double(post["zindex"].int ?? 5000000))
        cell.contentView.updateConstraints()
        cellCache[post["id"].intValue] = cell
        return cell
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath[1] == posts.count && posts.count != 0 {
            return readmoreCell
        }
        let post = posts[indexPath[1]]
        return getCell(post: post)
    }
    
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        if indexPath[1] >= self.posts.count {
            return []
        }
        let post = self.posts[indexPath[1]]
        // Reply
        let replyAction = UITableViewRowAction(style: .normal, title: "返信"){
            (action, index) -> Void in
            tableView.isEditing = false
            print("reply")
        }
        // ブースト
        let boostAction = UITableViewRowAction(style: .normal, title: "ブースト"){
            (action,index) -> Void in
            let post = self.posts[indexPath[1]]
            MastodonUserToken.getLatestUsed()!.post("statuses/"+post["id"].stringValue+"/reblog", params: [:]).then {_ in
                self.posts = self.posts.map({ (map_post) -> JSON in
                    var ret_post = map_post
                    if map_post["id"].int == post["id"].int {
                        ret_post["reblogged"].bool = true
                    }
                    return ret_post
                })
                action.backgroundColor = UIColor(colorLiteralRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
                tableView.isEditing = false
            }
            print("repost")
        }
        // like
        let likeAction = UITableViewRowAction(style: .normal, title: "ふぁぼ"){
            (action,index) -> Void in
            let post = self.posts[indexPath[1]]
            MastodonUserToken.getLatestUsed()!.post("statuses/"+post["id"].stringValue+"/favourite", params: [:]).then {_ in
                self.posts = self.posts.map({ (map_post) -> JSON in
                    var ret_post = map_post
                    if map_post["id"].int == post["id"].int {
                        ret_post["favourited"].bool = true
                    }
                    return ret_post
                })
                action.backgroundColor = UIColor(colorLiteralRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
                tableView.isEditing = false
            }
            print("like")
        }
        replyAction.backgroundColor = UIColor.init(colorLiteralRed: 0.95, green: 0.4, blue: 0.4, alpha: 1)
        if post["reblogged"].bool == true {
            boostAction.backgroundColor = UIColor.init(colorLiteralRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        } else {
            boostAction.backgroundColor = UIColor.init(colorLiteralRed: 0.3, green: 0.95, blue: 0.3, alpha: 1)
        }
        if post["favourited"].bool == true {
            likeAction.backgroundColor = UIColor.init(colorLiteralRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        } else {
            likeAction.backgroundColor = UIColor.init(colorLiteralRed: 0.9, green: 0.9, blue: 0.3, alpha: 1)
        }
        return [
            // replyAction,
            boostAction,
            likeAction
        ].reversed()
    }
    
    func appendNewPosts(posts: [JSON]) {
        var rows:[IndexPath] = []
        posts.forEach { (post) in
            var rpost = post
            timelineMinZIndex -= 1
            rpost["zindex"].int = timelineMinZIndex
            _ = self.getCell(post: rpost)
            self.posts.append(rpost)
            rows.append(IndexPath(row: self.posts.count-1, section: 0))
        }
        self.tableView.insertRows(at: rows, with: .automatic)
        self.maxPostCount += posts.count
    }
    
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return indexPath[0] == 0 && indexPath[1] < self.posts.count
    }
    
    /*
     // Override to support editing the table view.
     override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
     if editingStyle == .delete {
     // Delete the row from the data source
     tableView.deleteRows(at: [indexPath], with: .fade)
     } else if editingStyle == .insert {
     // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
     }
     }
     */
    
    /*
     // Override to support rearranging the table view.
     override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {
     
     }
     */
    
    /*
     // Override to support conditional rearranging of the table view.
     override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
     // Return false if you do not want the item to be re-orderable.
     return true
     }
     */
    
    /*
     // MARK: - Navigation
     
     // In a storyboard-based application, you will often want to do a little preparation before navigation
     override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
     // Get the new view controller using segue.destinationViewController.
     // Pass the selected object to the new view controller.
     }
     */
    

}
