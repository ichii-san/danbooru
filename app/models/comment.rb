class Comment < ActiveRecord::Base
  include Mentionable

  validate :validate_post_exists, :on => :create
  validate :validate_creator_is_not_limited, :on => :create
  validates_format_of :body, :with => /\S/, :message => 'has no content'
  belongs_to :post
  belongs_to :creator, :class_name => "User"
  belongs_to :updater, :class_name => "User"
  has_many :votes, :class_name => "CommentVote", :dependent => :destroy
  before_validation :initialize_creator, :on => :create
  before_validation :initialize_updater
  after_create :update_last_commented_at_on_create
  after_update(:if => lambda {|rec| CurrentUser.id != rec.creator_id}) do |rec|
    ModAction.log("comment ##{rec.id} updated by #{CurrentUser.name}")
  end
  after_destroy :update_last_commented_at_on_destroy
  after_destroy(:if => lambda {|rec| CurrentUser.id != rec.creator_id}) do |rec|
    ModAction.log("comment ##{rec.id} deleted by #{CurrentUser.name}")
  end
  attr_accessible :body, :post_id, :do_not_bump_post, :is_deleted, :as => [:member, :gold, :platinum, :builder, :janitor, :moderator, :admin]
  attr_accessible :is_sticky, :as => [:moderator, :admin]
  mentionable(
    :message_field => :body, 
    :user_field => :creator_id, 
    :title => "You were mentioned in a comment",
    :body => lambda {|rec, user_name| "You were mentioned in a \"comment\":/posts/#{rec.post_id}#comment-#{rec.id}\n\n---\n\n[i]#{rec.creator.name} said:[/i]\n\n#{ActionController::Base.helpers.excerpt(rec.body, user_name)}"}
    )

  module SearchMethods
    def recent
      reorder("comments.id desc").limit(6)
    end

    def body_matches(query)
      if query =~ /\*/ && CurrentUser.user.is_builder?
        where("body ILIKE ? ESCAPE E'\\\\'", query.to_escaped_for_sql_like)
      else
        where("body_index @@ plainto_tsquery(?)", query.to_escaped_for_tsquery_split).order("comments.id DESC")
      end
    end

    def hidden(user)
      where("score < ? and is_sticky = false", user.comment_threshold)
    end

    def visible(user)
      where("score >= ? or is_sticky = true", user.comment_threshold)
    end

    def deleted
      where("comments.is_deleted = true")
    end

    def undeleted
      where("comments.is_deleted = false")
    end

    def sticky
      where("comments.is_sticky = true")
    end

    def unsticky
      where("comments.is_sticky = false")
    end

    def bumping
      where("comments.do_not_bump_post = false")
    end

    def nonbumping
      where("comments.do_not_bump_post = true")
    end

    def post_tags_match(query)
      PostQueryBuilder.new(query).build(self.joins(:post)).reorder("")
    end

    def for_creator(user_id)
      user_id.present? ? where("creator_id = ?", user_id) : where("false")
    end

    def for_creator_name(user_name)
      for_creator(User.name_to_id(user_name))
    end

    def search(params)
      q = where("true")
      return q if params.blank?

      if params[:body_matches].present?
        q = q.body_matches(params[:body_matches])
      end

      if params[:id].present?
        q = q.where("id in (?)", params[:id].split(",").map(&:to_i))
      end

      if params[:post_id].present?
        q = q.where("post_id in (?)", params[:post_id].split(",").map(&:to_i))
      end

      if params[:post_tags_match].present?
        q = q.post_tags_match(params[:post_tags_match])
      end

      if params[:creator_name].present?
        q = q.for_creator_name(params[:creator_name])
      end

      if params[:creator_id].present?
        q = q.for_creator(params[:creator_id].to_i)
      end

      q = q.deleted if params[:is_deleted] == "true"
      q = q.undeleted if params[:is_deleted] == "false"

      q = q.sticky if params[:is_sticky] == "true"
      q = q.unsticky if params[:is_sticky] == "false"

      q = q.nonbumping if params[:do_not_bump_post] == "true"
      q = q.bumping if params[:do_not_bump_post] == "false"

      case params[:order]
      when "post_id", "post_id_desc"
        q = q.order("comments.post_id DESC, comments.id DESC")
      when "score", "score_desc"
        q = q.order("comments.score DESC, comments.id DESC")
      when "updated_at", "updated_at_desc"
        q = q.order("comments.updated_at DESC")
      else
        q = q.order("comments.id DESC")
      end

      q
    end
  end

  module VoteMethods
    def vote!(val)
      numerical_score = val == "up" ? 1 : -1
      vote = votes.create!(:score => numerical_score)

      if vote.is_positive?
        update_column(:score, score + 1)
      elsif vote.is_negative?
        update_column(:score, score - 1)
      end

      return vote
    end

    def unvote!
      vote = votes.where("user_id = ?", CurrentUser.user.id).first

      if vote
        if vote.is_positive?
          update_column(:score, score - 1)
        else
          update_column(:score, score + 1)
        end

        vote.destroy
      else
        raise CommentVote::Error.new("You have not voted for this comment")
      end
    end
  end

  extend SearchMethods
  include VoteMethods

  def initialize_creator
    self.creator_id = CurrentUser.user.id
    self.ip_addr = CurrentUser.ip_addr
  end

  def initialize_updater
    self.updater_id = CurrentUser.user.id
    self.updater_ip_addr = CurrentUser.ip_addr
  end

  def creator_name
    User.id_to_name(creator_id)
  end

  def updater_name
    User.id_to_name(updater_id)
  end

  def validate_post_exists
    errors.add(:post, "must exist") unless Post.exists?(post_id)
  end

  def validate_creator_is_not_limited
    if creator.is_comment_limited? && !do_not_bump_post?
      errors.add(:base, "You can only post #{Danbooru.config.member_comment_limit} comments per hour")
      false
    elsif creator.can_comment?
      true
    else
      errors.add(:base, "You can not post comments within 1 week of sign up")
      false
    end
  end

  def update_last_commented_at_on_create
    Post.where(:id => post_id).update_all(:last_commented_at => created_at)
    if Comment.where("post_id = ?", post_id).count <= Danbooru.config.comment_threshold && !do_not_bump_post?
      Post.where(:id => post_id).update_all(:last_comment_bumped_at => created_at)
    end
    true
  end

  def update_last_commented_at_on_destroy
    other_comments = Comment.where("post_id = ? and id <> ?", post_id, id).order("id DESC")
    if other_comments.count == 0
      Post.where(:id => post_id).update_all(:last_commented_at => nil)
    else
      Post.where(:id => post_id).update_all(:last_commented_at => other_comments.first.created_at)
    end

    other_comments = other_comments.where("do_not_bump_post = FALSE")
    if other_comments.count == 0
      Post.where(:id => post_id).update_all(:last_comment_bumped_at => nil)
    else
      Post.where(:id => post_id).update_all(:last_comment_bumped_at => other_comments.first.created_at)
    end

    true
  end

  def editable_by?(user)
    creator_id == user.id || user.is_moderator?
  end

  def hidden_attributes
    super + [:body_index]
  end

  def method_attributes
    super + [:creator_name, :updater_name]
  end

  def delete!
    update({ :is_deleted => true }, :as => CurrentUser.role)
  end

  def undelete!
    update({ :is_deleted => false }, :as => CurrentUser.role)
  end
end

Comment.connection.extend(PostgresExtensions)
