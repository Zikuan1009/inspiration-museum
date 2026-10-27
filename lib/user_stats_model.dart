/// 个人主页统计。全部来自云端 count，缺省为 0。
class UserStatsModel {
  const UserStatsModel({
    this.posts = 0,
    this.likes = 0,
    this.followers = 0,
    this.following = 0,
  });

  final int posts;
  final int likes;
  final int followers;
  final int following;
}
