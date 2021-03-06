class ReportsController < ApplicationController
  before_filter :member_only
  before_filter :gold_only, :only => [:similar_users]
  before_filter :moderator_only, :only => [:post_versions, :post_versions_create]

  def user_promotions
    @report = Reports::UserPromotions.new
  end

  def janitor_trials
    @report = Reports::JanitorTrials.new
  end

  def contributors
    @report = Reports::Contributors.new
  end

  def uploads
    @report = Reports::Uploads.new(params[:min_date], params[:max_date], params[:queries])
  end

  def similar_users
    @report = Reports::UserSimilarity.new(CurrentUser.id)
    @presenter = UserSimilarityPresenter.new(@report)
  end

  def post_versions
  end

  def post_versions_create
    @report = Reports::PostVersions.new(params[:tag], params[:type])
  end
end
