//
//  MastodonPostDetailTableViewController.swift
//  iMast
//
//  Created by rinsuki on 2017/07/14.
//  Copyright © 2017年 rinsuki. All rights reserved.
//

import UIKit
import SwiftyJSON
import SafariServices

class MastodonPostDetailTableViewController: UITableViewController, UITextViewDelegate {

    @IBOutlet weak var firstCell: UITableViewCell!
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var iconView: UIImageView!
    @IBOutlet weak var userNameView: UILabel!
    @IBOutlet weak var userScreenNameView: UILabel!
    @IBOutlet weak var actionCountCell: UITableViewCell!
    @IBOutlet weak var favouriteButton: UIButton!
    @IBOutlet weak var boostButton: UIButton!
    @IBOutlet weak var moreButton: UIButton!
    @IBOutlet weak var postStackView: UIStackView!
    @IBOutlet weak var imageStackView: UIStackView!
    @IBOutlet weak var nsfwGuardView: NSFWGuardView!
    var loadAfter = false
    var isLoaded = false
    var post: MastodonPost?
    var cwOpen = false
    var isFavorited = false {
        didSet {
            favouriteButton.setTitleColor(isFavorited ?
                UIColor(
                    red: 1,
                    green: 0.8,
                    blue: 0.01,
                    alpha: 1
                )
              : UIColor.darkGray
            , for: .normal)
        }
    }
    var isBoosted = false {
        didSet {
            boostButton.setTitleColor(isBoosted ?
                UIColor(
                    red: 0.1,
                    green: 0.6,
                    blue: 1,
                    alpha: 1
                )
                : UIColor.darkGray
            , for: .normal)
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        isLoaded = true
        if loadAfter {
            loadAfter = false
            load(post: post!)
        }
        tableView.rowHeight = UITableViewAutomaticDimension
        textView.sizeToFit()
        textView.delegate = self
    }
    
    func load(post: MastodonPost, spoiler: Bool = false) {
        self.post = post
        if isLoaded == false {
            loadAfter = true
            return
        }
        print(post)
        var html = "<style>*{font-size:14px;font-family: sans-serif;padding:0;margin:0;}</style>"
        let postHtml = post.status.emojify(custom_emoji: post.emojis, profile_emoji: post.profileEmojis).replace("</p><p>", "<br /><br />").replace("<p>", "").replace("</p>", "")
        if post.spoilerText != "" {
            html += post.spoilerText.replace("<", "&lt;").replace(">", "&gt;").replace("\n", "<br>")
            if !spoiler {
                html += "<br><a href=\"imast://cw/show\">(CWの内容を読む)</a><br>"
            } else {
                html += "<br><a href=\"imast://cw/hide\">(CWの内容を畳む)</a><br>"
                html += postHtml
            }
        } else {
            html += postHtml
        }
        let attrStr = html.parseText2HTML()
        if attrStr == nil {
            textView.text = post.status
                .pregReplace(pattern: "\\<br /\\>", with: "\n")
                .pregReplace(pattern: "\\<.+?\\>", with: "")
                .replace("&lt;", "<") // HTMLのエスケープを解く
                .replace("&gt;", ">")
                .replace("&apos;", "\"")
                .replace("&quot;", "'")
                .replace("&amp;", "&")
        } else {
            textView.attributedText = attrStr
        }
        var iconUrl = post.account.avatarUrl
        if iconUrl.count >= 1 && iconUrl[iconUrl.startIndex] == "/" {
            iconUrl = "https://"+MastodonUserToken.getLatestUsed()!.app.instance.hostName+iconUrl
        }
        userNameView.text = (post.account.name != "" ? post.account.name : post.account.screenName).emojify()
        userScreenNameView.text = "@"+post.account.acct
        iconView.sd_setImage(with: URL(string: iconUrl))
        iconView.ignoreSmartInvert()
        var actionText = ""
        if post.repostCount > 0 {
            actionText += "%d件のブースト ".format(post.repostCount)
        }
        if post.favouritesCount > 0 {
            actionText += "%d件のふぁぼ ".format(post.favouritesCount)
        }
        if let app = post.application {
            actionText += "via \(app.name) "
        }
        actionCountCell.textLabel?.text = actionText
        
        iconView.isUserInteractionEnabled = true
        iconView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapUser)))
        userNameView.isUserInteractionEnabled = true
        userNameView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapUser)))
        userScreenNameView.isUserInteractionEnabled = true
        userScreenNameView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapUser)))

        isFavorited = post.favourited
        isBoosted = post.reposted
        
        let thumbnail_height = Defaults[.thumbnailHeight]
        if nsfwGuardView.isUserInteractionEnabled {
            nsfwGuardView.isHidden = !post.sensitive && post.attachments.count > 0
        }

        for subview in self.imageStackView.arrangedSubviews {
            self.imageStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        if thumbnail_height != 0 {
            post.attachments.enumerated().forEach({ (index, media) in
                let imageView = UIImageView()
                imageView.sd_setImage(with: URL(string: media.previewUrl))
                imageView.ignoreSmartInvert()
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                imageView.layoutIfNeeded()
                imageView.heightAnchor.constraint(equalToConstant: CGFloat(thumbnail_height)).isActive=true
                imageView.isUserInteractionEnabled = true
                imageView.tag = 100+index
                imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapImage)))
                self.imageStackView.addArrangedSubview(imageView)
            })
        } else {
            for subview in self.imageStackView.arrangedSubviews {
                self.imageStackView.removeArrangedSubview(subview)
                subview.removeFromSuperview()
            }
        }
        postStackView.layoutIfNeeded()
    }
    
    @objc func tapImage(sender: UITapGestureRecognizer) {
        guard let post = self.post?.repost ?? self.post else {
            return
        }
        let media = post.attachments[sender.view!.tag-100]
        if media.url.hasSuffix("webm") && openVLC(media.url) {
            return
        }
        let safari = SFSafariViewController(url: URL(string: media.url)!)
        self.present(safari, animated: true, completion: nil)
    }
    
    @IBAction func replyTapped(_ sender: Any) {
        guard let post = self.post?.repost ?? self.post else {
            return
        }
        let storyboard = UIStoryboard(name: "NewPost", bundle: nil)
        // let newVC = storyboard.instantiateViewController(withIdentifier: "topVC") as! UserProfileTopViewController
        let newVC = storyboard.instantiateInitialViewController() as! NewPostViewController
        newVC.replyToPost = post
        newVC.title = "返信"
        self.navigationController?.pushViewController(newVC, animated: true)
    }
    @IBAction func boostTapped(_ sender: Any) {
        guard let post = self.post?.repost ?? self.post else {
            return
        }
        if !isBoosted {
            MastodonUserToken.getLatestUsed()!.repost(post: post).then({ (res) in
                self.isBoosted = true
            })
        } else {
            MastodonUserToken.getLatestUsed()!.unrepost(post: post).then({ (res) in
                self.isBoosted = false
            })
        }
        print(isBoosted)
    }
    @IBAction func favouriteTapped(_ sender: Any) {
        guard let post = self.post?.repost ?? self.post else {
            return
        }
        if !isFavorited {
            MastodonUserToken.getLatestUsed()!.favourite(post: post).then({ (res) in
                self.isFavorited = true
            })
        } else {
            MastodonUserToken.getLatestUsed()!.unfavourite(post: post).then({ (res) in
                self.isFavorited = false
            })
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath[0] == 0 && indexPath[1] == 0 {
            return textView.frame.minY + textView.frame.height + 16 + imageStackView.frame.height
        }
        if indexPath[0] == 0 && indexPath[1] == 1 {
            if (actionCountCell.textLabel?.text ?? "") == ""{
                return 0
            }
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
    @objc func tapUser(sender: UITapGestureRecognizer) {
        guard let post = self.post?.repost ?? self.post else {
            return
        }
        let newVC = openUserProfile(user: post.account)
        self.navigationController?.pushViewController(newVC, animated: true)
    }
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
        if let post = self.post, URL.scheme == "imast" {
            if URL.absoluteString == "imast://cw/show" {
                self.load(post: post, spoiler: true)
            }
            if URL.absoluteString == "imast://cw/hide" {
                self.load(post: post, spoiler: false)
            }
            self.tableView.reloadData()
            return false
        }
        let safari = SFSafariViewController(url: URL)
        self.present(safari, animated: true, completion: nil)
        return false
    }
    @IBAction func moreButtonTapped(_ sender: Any) {
        guard let post = self.post?.repost ?? self.post else {
            return
        }
        let actionSheet = UIAlertController(title: "アクション", message: "", preferredStyle: UIAlertControllerStyle.actionSheet)
        actionSheet.popoverPresentationController?.sourceView = self.moreButton as UIView
        actionSheet.popoverPresentationController?.sourceRect = (self.moreButton as UIView).bounds
        // ---
        actionSheet.addAction(UIAlertAction(title: "文脈", style: UIAlertActionStyle.default, handler: { action in
            MastodonUserToken.getLatestUsed()?.context(post: post).then { res in
                print(res)
                let posts = res.ancestors + [post] + res.descendants
                let bunmyakuVC = TimeLineTableViewController()
                bunmyakuVC.posts = posts
                bunmyakuVC.isReadmoreEnabled = false
                bunmyakuVC.title = "文脈"
                self.navigationController?.pushViewController(bunmyakuVC, animated: true)
            }
        }))
        if MastodonUserToken.getLatestUsed()!.screenName == post.account.acct {
            actionSheet.addAction(UIAlertAction(title: "削除", style: UIAlertActionStyle.destructive, handler: { (action) in
                self.confirm(title: "投稿の削除", message: Defaults[.deleteTootTeokure] ? "失った信頼はもう戻ってきませんが、本当にこのトゥートを削除しますか?" : "この投稿を削除しますか?", okButtonMessage: "削除", style: .destructive).then({ (res) in
                    if res == false {
                        return
                    }
                    MastodonUserToken.getLatestUsed()!.delete(post: post).then({ (res) in
                        self.navigationController?.popViewController(animated: true)
                        self.alert(title: "投稿を削除しました", message: "投稿を削除しました。\n※画面に反映されるには時間がかかる場合があります")
                    })
                })
            }))
        }
        actionSheet.addAction(UIAlertAction(title: "通報", style: UIAlertActionStyle.destructive, handler: { (action) in
            let newVC = MastodonPostAbuseViewController()
            newVC.targetPost = post
            newVC.placeholder = "『\(post.status.pregReplace(pattern: "<.+?>", with: ""))』を通報します。\n詳細をお書きください（必須ではありません）"
            self.navigationController?.pushViewController(newVC, animated: true)
        }))
        actionSheet.addAction(UIAlertAction(title: "キャンセル", style: UIAlertActionStyle.cancel))
        self.present(actionSheet, animated: true, completion: nil)
    }

    // MARK: - Table view data source

    /*
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "reuseIdentifier", for: indexPath)

        // Configure the cell...

        return cell
    }
    */

    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

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
