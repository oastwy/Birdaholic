import 'package:flutter/material.dart';

/// 新手图文教程：覆盖打卡/预习/鸟种页/数据包/eBird/上传/反馈，
/// 并解释「什么是 API、如何申请」以及「抽象图」难度理念。纯文字，无需联网。
class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  static const _green = Color(0xFF2d5016);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新手教程')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: const [
          _Lead(
            '欢迎来到鸟瘾综合征！这是一个帮你「认鸟」的工具：观鸟前预习、观鸟后复习，'
            '用闪卡和打卡把鸟图、鸟鸣和辨识特征记牢。下面按使用流程讲一遍。',
          ),
          _Sec('① 三步上手', [
            '装数据包：设置 → 数据包管理，先装内置「全国常见 100」，不填任何 Key 也能直接开始。',
            '预习：在「预习」页上下滑浏览鸟种，看图、听声、记特征。',
            '打卡：回首页点「打卡」（首页有 打卡 / 预习 / 复习 三个按钮），看图 / 听声辨认——上滑表示认识、下滑表示不认识，10 张一组。',
          ]),
          _Sec('② 打卡 / 闪卡筛选怎么玩', [
            '每组默认 10 张，可在「闪卡设置」里改。答错的鸟会进复习，多见几次就记住了。',
            'App 重启后第一次点「打卡」或「复习」，会先停在「闪卡筛选页」让你配置；点「开始」后，本次使用里打卡 / 复习都直接沿用上次配置，不再每次都弹。',
            '筛选页里可选：学习模式 / 测试模式；判断题 / 选择题；音频闪卡 / 图片闪卡；范围（全部 / 已学习 / 未学习 / 不熟悉 / 收藏 / 未见过）；以及数据包和地点。',
            '顺序：随机 / 分类关系（按目科属种排）/ 可能性（按近期 eBird 观测，把最可能遇到的鸟排前——需先按 eBird 地点筛选）。',
            '想每次一进就全屏、不弹筛选页，在「闪卡设置」打开「开始打卡直接进入全屏」。',
            '看答案时，点鸟的中文 / 英文 / 拉丁名，就能进入「了解此鸟」详情页，看更多图和辨识特征。',
          ]),
          _Sec('③ 鸟种页（预习详情）', [
            '上半是照片：左右滑看同一种鸟的多张图，点图可看大图。',
            '下半「辨识特征」和「鸟鸣」左右滑切换，不用在一长页里来回滚。',
            '右上角可收藏；有上传权限时还能上传你自己拍的图 / 录的鸟鸣。',
          ]),
          _Sec('④ 打卡日历 / 今日听声挑战', [
            '首页有一张打卡日历：默认显示最近两周（绿色＝当天完成了打卡），点「展开整月」看完整月历，标题处显示 🔥连续 N 天。',
            '日历上方有「今日听声挑战」：听鸟鸣猜鸟种、每天 5 题，当作每日小测、轻松保持手感。',
            '坚持连续打卡，是记住鸟最有效的办法——每天几分钟就够。',
          ]),
          _Sec('⑤ 关于「抽象图 / 难度图」——很重要', [
            '你可能会刷到一些「不太标准」的鸟图：角度刁钻、距离远、有点糊、只露一部分。这是有意为之，不是凑数。',
            '真实观鸟里，鸟很少给你拍标准证件照。只有用不同难度的图训练，才能练出在野外真正认得出来的眼力。',
            '所以图越「抽象但仍能辨认」，训练价值越高。也非常欢迎你上传这样的图——只要还能看出是哪种鸟，就是好素材。',
            '唯一的底线：请不要上传完全无法辨认的图。',
          ]),
          _Sec('⑥ 什么是「API」？怎么申请？', [
            'API 可以简单理解成 App 和服务器之间的「数据接口」。本 App 会用到两类：',
            '• eBird API：用来按地点查「附近会出现哪些鸟」。需要你自己去 ebird.org 申请一个免费 API Key（在 ebird.org/api/keygen 生成），填到「设置 → API Key 与上传身份」。',
            '• 本站上传接口：你把鸟图 / 鸟鸣分享给大家时用，需要「上传权限」。',
            '申请上传权限：设置 → 申请上传权限 → 提交即可。无需注册，不收手机号 / 微信 / 邮箱 / 姓名，只发送一个本机匿名申请号和 App 版本号。管理员审核通过后，App 会自动获得上传身份，你就能上传了。',
          ]),
          _Sec('⑦ eBird 地点筛选 / 看自己的 life list', [
            '在打卡 / 预习里可以按 eBird 地点，筛出「这个地方会出现的鸟」来针对性练。',
            '想看自己的观鸟清单、筛出还没见过的新种（设置 → 我的观鸟清单）：可导入 eBird 导出的 MyEBirdData.csv，或「中国观鸟记录中心」(birdreport.cn) 导出的「鸟种数据导出.xlsx」，也可在鸟种页手动标记「已见 / 未见」。',
            '导入只读「学名 / 拉丁名」一列，可重复导入更新；记录中心与 App 分类偶有差异时，已内置同义词映射自动对齐，绝大多数能匹配上。',
          ]),
          _Sec('⑧ 反馈与通知', [
            '发现鸟种信息有错、或想说点什么，用「设置 → 反馈与通知」提交。',
            '管理员的回复也会出现在这里——同一台手机就能收到，不用注册。',
          ]),
          _Closing('祝你看见更多身边的鸟 🐦'),
        ],
      ),
    );
  }
}

class _Lead extends StatelessWidget {
  final String text;
  const _Lead(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14.5, height: 1.5),
      ),
    );
  }
}

class _Sec extends StatelessWidget {
  final String title;
  final List<String> points;
  const _Sec(this.title, this.points);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: TutorialScreen._green,
              ),
            ),
            const SizedBox(height: 10),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(p, style: const TextStyle(fontSize: 14, height: 1.5)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Closing extends StatelessWidget {
  final String text;
  const _Closing(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: TutorialScreen._green,
          ),
        ),
      ),
    );
  }
}
